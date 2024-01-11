# This is a justfile. See https://github.com/casey/just
# This is only used for local development. The builds made on the Fedora
# infrastructure are run in Pungi.

# Set a default for some recipes
default_variant := "n62-default"
force_nocache := "true"
# Enable to sign the efi boot files, kernel and kernel modules for secure boot with a provided key
secure_boot := "true"
# The default architecture we are building for. Set by default to the system architecture
default_arch := "$(arch)"
default_secure_boot_db_sign_key_dir := "secureBoot"

# Default is to compose PhotonPonyOS and PhotonPonyOSBase
all gpg_key="":
    just compose n62-default
    just lorax n62-default
    just export-release n62-default {{gpg_key}}
    just sign-all n62-default {{gpg_key}}

    just compose n62-base
    just lorax n62-base
    just export-release n62-base {{gpg_key}}
    just sign-all n62-base {{gpg_key}}

    just fix-ownership

# Basic validation to make sure the manifests are not completely broken
validate:
    ./ci/validate.py

# Output the processed manifest for a given variant (defaults to Silverblue)
manifest variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    rpm-ostree compose tree --print-only --repo=repo ppos-{{variant}}.yaml
    just fix-ownership

sign-repo variant=default_variant gpg_key="" repo="repo":
    #!/bin/bash
    set -euxo pipefail

    # Get the user that invoked this call so we can determine the GPG home dir later
    if [ $SUDO_USER ]; then REAL_USER="$SUDO_USER"; else REAL_USER="$(whoami)"; fi

    # Get the latest commit
    repo={{repo}}
    ref="$(rpm-ostree compose tree --print-only --repo=${repo} ppos-{{variant}}.yaml | jq -r '.ref')"
    commits="$(ostree log --repo=${repo} $ref | grep '^commit' | sed 's/commit //g')"
    commitsArr=($commits)

    # Sign all commits
    for commit in "${commitsArr[@]}"
    do
        ostree gpg-sign --gpg-homedir=/home/$REAL_USER/.gnupg/ --repo=repo "${commit}" '{{gpg_key}}'
        echo "Commit '${commit}' signed."
    done

    # Sign
    ostree gpg-sign --repo=${repo} $commit {{gpg_key}} --gpg-homedir=/home/$REAL_USER/.gnupg/

sign-iso gpg_key="":
    #!/bin/bash
    set -euxo pipefail

    # Get the user that invoked this call so we can determine the GPG home dir later
    if [ $SUDO_USER ]; then REAL_USER="$SUDO_USER"; else REAL_USER="$(whoami)"; fi
    # export GNUPGHOME=/home/$REAL_USER/.gnupg/
    pushd iso
    for i in $(find . -maxdepth 1 -type f -name '*.iso' -printf '%f\n')
    do
        RAW_NAME="$(basename $i -s)"

        rm -rf $RAW_NAME.sha512
        sha512sum $i > $RAW_NAME.sha512

        rm -rf $RAW_NAME.sha512.sig
        GNUPGHOME=/home/$REAL_USER/.gnupg/ gpg --output $RAW_NAME.sha512.sig --sign --local-user $REAL_USER --default-key {{gpg_key}} $RAW_NAME.sha512
    done
    popd

sign-all variant=default_variant gpg_key="":
    #!/bin/bash
    set -euxo pipefail

    just sign-repo {{variant}} {{gpg_key}}
    just sign-iso {{gpg_key}}

export-release variant=default_variant gpg_key="":
    #!/bin/bash
    set -euxo pipefail

    ref="$(rpm-ostree compose tree --print-only --repo=repo ppos-{{variant}}.yaml | jq -r '.ref')"
    version=$(ostree log --repo=repo ${ref} | grep '^Version:' | head -n 1 | sed 's/Version: //g' | tr '[:blank:]' '_')
    output_repo_path="release/${version}"

    # Prepare the output directory
    rm -rf ${output_repo_path}*
    mkdir -p ${output_repo_path}
    ostree init --repo=${output_repo_path} --mode=archive

    # Create local copy
    ostree pull-local --repo=${output_repo_path} -v repo ${ref}

    # Sign the resulting commit/repo
    just sign-repo {{variant}} {{gpg_key}} ${output_repo_path}

    # Compress the result
    pushd release/${version}
    # Set to best compression since it does not change anything in the result since most of the parts are already compressed anyway
    zip -r -q -9 ../${version}.zip ./*
    popd
    rm -rf release/${version}

compose-post-script secure_boot_db_sign_key_dir=default_secure_boot_db_sign_key_dir:
    #!/bin/bash
    set -euxo pipefail

    # Based on: https://sysguides.com/fedora-uefi-secure-boot-with-custom-keys/
    baseDir="tmp/rootfs"
    keyBasePath="$(pwd)/secureBoot"

    # Copy the public key to the new root file system
    mkdir -p ${baseDir}/usr/etc/pki/aps/secureBoot/{auth,cfg,esl,ms,oem} || exit 1
    chmod -R 700 ${baseDir}/usr/etc/pki/aps || exit 1

    # Check if ephermal keys exist if not generate them
    if [ ! -f secureBoot/db.key ] || [ ! -f secureBoot/db.pem ] || [ ! -f secureBoot/PK.cfg ]; then just gen-secureboot-ephemeral-key; fi


    cp secureBoot/db.key ${baseDir}/usr/etc/pki/aps/secureBoot || exit 1
    chmod 600 ${baseDir}/usr/etc/pki/aps/secureBoot/db.key
    cp secureBoot/db.pem ${baseDir}/usr/etc/pki/aps/secureBoot || exit 1
    chmod 600 ${baseDir}/usr/etc/pki/aps/secureBoot/db.pem
    cp secureBoot/PK.cfg ${baseDir}/usr/etc/pki/aps/secureBoot/cfg || exit 1
    chmod 600 ${baseDir}/usr/etc/pki/aps/secureBoot/cfg/PK.cfg

    # Sign everything
    chroot ${baseDir} /bin/bash -x << 'EOF'
    keyBasePath="/usr/etc/pki/aps/secureBoot"

    # Sign the kernel
    find /usr/lib/modules -name vmlinuz* | sort | uniq | while read -r path; do
        fullPath=$(realpath ${path})
        echo "Signing kernel at: ${fullPath}"
        sbsign ${fullPath} --key ${keyBasePath}/db.key --cert ${keyBasePath}/db.pem --output ${fullPath} || exit 1
    done
    popd

    # Sign the kernel modules
    # We expect there to be only a single or no kernel(-devel)
    kmodCount=$(find /usr/lib/modules -name spcm4.ko.xz | wc -l)
    if [[ ${kmodCount} -ne 0 ]]; then
        kmodPath=$(find /usr/lib/modules -name spcm4.ko.xz)
        kmodPathDir=$(dirname ${kmodPath})
        signFilePath=$(find /usr/src/kernels -name sign-file)

        pushd ${kmodPathDir}
        unxz -f spcm4.ko.xz || exit 1
        ${signFilePath} sha256 ${keyBasePath}/db.key ${keyBasePath}/db.pem spcm4.ko || exit 1
        xz spcm4.ko spcm4.ko.xz || true
        popd
    else
        echo "No spcm4 kernel module found. Skipping kernel module signing."
    fi

    # Sign all boot related efi binaries
    baseEfiPath="/usr/lib/ostree-boot/efi/EFI/fedora"
    find ${baseEfiPath} -name *.efi | while read -r path; do
        echo "Signing: ${path}"

        # Not all efi files are signed. So skip removing signatures for all that are not signed.
        sigCount=$(pesign -S -i ${path} | grep "Signing time" | wc -l)
        if [[ ${sigCount} -ne 0 ]]; then
            echo "Removing existing signature from: ${path}"
            pesign -r -u0 -i ${path} -o ${path}.empty || exit 1
        else
            echo "No need to remove existing signature from '${path}'. There is none. Just copying..."
            cp ${path} ${path}.empty
        fi
        
        sbsign ${path}.empty --key ${keyBasePath}/db.key --cert ${keyBasePath}/db.pem --output ${path} || exit 1
        rm -f ${path}.empty
    done
    EOF
    rm -f ${baseDir}/usr/etc/pki/aps/secureBoot/db.key || exit 1

# Compose a specific variant of Fedora (defaults to Silverblue)
compose variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "n62-default")
            variant_pretty="PhotonPonyOS-N62-Default"
            ;;
        "n62-base")
            variant_pretty="PhotonPonyOS-N62-Base"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    on_failure() {
        just archive {{variant}} repo
    }
    trap "on_failure" ERR

    ./ci/validate.py || (echo "Failed manifest validation" && exit 1)

    just prep

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    # TODO: Pull latest build for the current release
    # ostree pull ...

    version="$(rpm-ostree compose tree --print-only --repo=repo ppos-${variant}.yaml | jq -r '."mutate-os-release"')"

    echo "Composing ${variant_pretty} ${version}.${buildid} ..."
    # To debug with gdb, use: gdb --args ...

    INSTALL_ARGS="--repo=repo --cachedir=cache --unified-core"
    POSTPROCESS_ARGS="--unified-core"
    COMMIT_ARGS="--repo=repo --unified-core"

    if [[ {{force_nocache}} == "true" ]]; then
        INSTALL_ARGS+=" --force-nocache"
    fi
    
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        SUDO="sudo rpm-ostree"
    fi

    rm -rf tmp
    LOG_FILE="logs/${variant}_${version}_${buildid}.${timestamp}.log"
    ${CMD} compose install ${INSTALL_ARGS} "ppos-${variant}.yaml" tmp |& tee ${LOG_FILE}
    just compose-post-script # Sign the kernel, bootloader and kernel modules
    ${CMD} compose postprocess ${POSTPROCESS_ARGS} tmp/rootfs "ppos-${variant}.yaml" |& tee ${LOG_FILE}
    ${CMD} compose commit ${COMMIT_ARGS} --add-metadata-string="version=${variant_pretty} ${version}.${buildid}" "ppos-${variant}.yaml" tmp/rootfs |& tee ${LOG_FILE}
    
    just compose-finalize

# Last steps from the compose recipe that can easily fail when the sudo timeout is reached
compose-finalize:
    #!/bin/bash
    set -euxo pipefail

    if [[ ${EUID} -ne 0 ]]; then
        sudo chown --recursive "$(id --user --name):$(id --group --name)" repo cache
    fi
    ostree summary --repo=repo --update
    just fix-ownership

# Get ostree repo log for a given variant
log variant=default_variant arch=default_arch:
    ostree log --repo repo fedora/rawhide/{{arch}}/{{variant}}

# Get the diff between two ostree commits
diff target origin:
    ostree diff --repo repo --fs-diff {{target}} {{origin}}

# Preparatory steps before starting a compose. Also ensure the ostree repo is initialized
prep:
    #!/bin/bash
    set -euxo pipefail

    mkdir -p repo cache logs
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=archive
        popd > /dev/null || exit 1
    fi
    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

# Clean up everything
clean-all:
    just clean-repo
    just clean-cache

# Only clean the ostree repo
clean-repo:
    rm -rf ./repo

# Only clean the package and repo caches
clean-cache:
    rm -rf ./cache

# Run from inside a container
podman:
    podman run --rm -ti --volume $PWD:/srv:rw --workdir /srv --privileged quay.io/fedora-ostree-desktops/buildroot

# Update the container image
podman-pull:
    podman pull quay.io/fedora-ostree-desktops/buildroot

# Build an ISO
lorax variant=default_variant arch=default_arch:
    #!/bin/bash
    set -euxo pipefail

    rm -rf iso
    # Do not create the iso directory or lorax will fail
    mkdir -p tmp cache/lorax

    arch={{arch}}
    variant={{variant}}
    case "${variant}" in
        "n62-default")
            variant_pretty="PhotonPonyOS-N62-Default"
            volid_sub="PPOS_N62_DEFAULT"
            ;;
        "n62-base")
            variant_pretty="PhotonPonyOS-N62-Base"
            volid_sub="PPOS_N62_BASE"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    on_failure() {
        # Archive both repo & iso here as we only archive the repo after the
        # lorax step in the non-failing case
        just archive {{variant}} repo
        just archive {{variant}} iso
    }
    trap "on_failure" ERR

    if [[ ! -d fedora-lorax-templates ]]; then
        git clone https://pagure.io/fedora-lorax-templates.git
    else
        pushd fedora-lorax-templates > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    version_number="$(rpm-ostree compose tree --print-only --repo=repo ppos-${variant}.yaml | jq -r '."mutate-os-release"')"
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version_pretty="Rawhide"
        version="rawhide"
    else
        version_pretty="${version_number}"
        version="${version_number}"
    fi
    source_url="https://kojipkgs.fedoraproject.org/compose/${version}/latest-Fedora-${version_pretty}/compose/Everything/{{arch}}/os/"
    volid="Fedora-${volid_sub}-ostree-{{arch}}-${version_pretty}"

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    pwd="$(pwd)"

    lorax \
        --product=PhotonPonyOS \
        --version=${version_pretty} \
        --release=${buildid} \
        --source="${source_url}" \
        --variant="${variant_pretty}" \
        --nomacboot \
        --isfinal \
        --buildarch=${arch} \
        --volid="${volid}" \
        --logfile=${pwd}/logs/lorax.log \
        --tmp=${pwd}/tmp \
        --cachedir=cache/lorax \
        --rootfs-size=8 \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-configure-repo.tmpl \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-embed-repo.tmpl \
        --add-template-var=ostree_install_repo=file://${pwd}/repo \
        --add-template-var=ostree_update_repo=file://${pwd}/repo \
        --add-template-var=ostree_osname=ppos \
        --add-template-var=ostree_oskey=ppos-${version_number}-primary \
        --add-template-var=ostree_contenturl=mirrorlist=https://ostree.fedoraproject.org/mirrorlist \
        --add-template-var=ostree_install_ref=ppos/${version}/${arch}/${variant} \
        --add-template-var=ostree_update_ref=ppos/${version}/${arch}/${variant} \
        ${pwd}/iso/linux

    mv iso/linux/images/boot.iso iso/Fedora-${volid_sub}-ostree-${arch}-${version_pretty}-${buildid}.iso
    just kickstart iso/Fedora-${volid_sub}-ostree-${arch}-${version_pretty}-${buildid}.iso iso/KS-Fedora-${volid_sub}-ostree-${arch}-${version_pretty}-${buildid}.iso
    just fix-ownership

kickstart inputIso outputIso:
    #!/bin/bash
    set -euxo pipefail
    mkksiso $(pwd)/ppos.ks {{inputIso}} {{outputIso}}

fix-ownership:
    #!/bin/bash
    set -euxo pipefail

    if [ $SUDO_USER ]; then user="$SUDO_USER"; else user="$(whoami)"; fi
    
    if [ -d iso ]; then chown -R ${user}:${user} iso; fi
    if [ -d release ]; then chown -R ${user}:${user} release; fi
    if [ -d repo ]; then chown -R ${user}:${user} repo; fi

gen-secureboot-ephemeral-key:
    #!/bin/bash
    set -uxo pipefail

    mkdir -p secureBoot
    touch secureBoot/PK.cfg
    
    echo "[ req ]
    default_bits         = 4096
    encrypt_key          = no
    string_mask          = utf8only
    utf8                 = yes
    prompt               = no
    distinguished_name   = my_dist_name
    x509_extensions      = my_x509_exts
 
    [ my_dist_name ]
    commonName           = Ephemeral Platform Key
    emailAddress         = not-a-vald-production-key@example.com

    [ my_x509_exts ]
    keyUsage             = digitalSignature
    extendedKeyUsage     = codeSigning
    basicConstraints     = critical,CA:FALSE
    subjectKeyIdentifier = hash" > secureBoot/PK.cfg



    openssl req -x509 -sha256 -days 5490 -outform PEM -config secureBoot/PK.cfg -keyout secureBoot/PK.key -out secureBoot/PK.pem
    cp -v secureBoot/{PK,KEK}.cfg
    sed -i 's/Platform Key/Key Exchange Key/g' secureBoot/KEK.cfg
    openssl req -x509 -sha256 -days 5490 -outform PEM -config secureBoot/KEK.cfg keyout secureBoot/KEK.key -out secureBoot/KEK.pem
    
    cp -v secureBoot/{PK,db}.cfg
    sed -i 's/Platform Key/Signature Database/g' secureBoot/db.cfg
    
    openssl req -x509 -sha256 -days 5490 -outform PEM -config secureBoot/db.cfg -keyout secureBoot/db.key -out secureBoot/db.pem
    openssl x509 -text -noout -inform PEM -in secureBoot/db.pem
