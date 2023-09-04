# This is a justfile. See https://github.com/casey/just
# This is only used for local development. The builds made on the Fedora
# infrastructure are run in Pungi.

# Set a default for some recipes
default_variant := "silverblue"
# Default to unified compose now that it works for Silverblue & Kinoite builds
unified_core := "true"
# unified_core := "false"
# force_nocache := "true"
force_nocache := "false"
# The default architecture we are building for. Set by default to the system architecture
default_arch := "$(arch)"

# Default is to compose PhotonPonyOS and PhotonPonyOSBase
all:
    just compose photon-pony
    just compose photon-pony-base

# Basic validation to make sure the manifests are not completely broken
validate:
    ./ci/validate

# Sync the manifests with the content of the comps groups
comps-sync:
    #!/bin/bash
    set -euxo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    else
        pushd fedora-comps > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${default_variant}.yaml | jq -r '."automatic-version-prefix"')"
    ./comps-sync.py --save fedora-comps/comps-f${version}.xml.in
    just fix-ownership

# Output the processed manifest for a given variant (defaults to Silverblue)
manifest variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "photon-pony")
            variant_pretty="PhotonPonyOS"
            ;;
        "photon-pony-base")
            variant_pretty="PhotonPonyOSBase"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    rpm-ostree compose tree --print-only --repo=repo fedora-{{variant}}.yaml
    just fix-ownership

sign-repo variant=default_variant gpg_key="" repo="repo":
    #!/bin/bash
    set -euxo pipefail

    # Get the user that invoked this call so we can determine the GPG home dir later
    if [ $SUDO_USER ]; then REAL_USER="$SUDO_USER"; else REAL_USER="$(whoami)"; fi

    # Get the latest commit
    repo={{repo}}
    ref="$(rpm-ostree compose tree --print-only --repo=${repo} fedora-{{variant}}.yaml | jq -r '.ref')"
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

sign-iso variant=default_variant gpg_key="":
    #!/bin/bash
    set -euxo pipefail

    # Get the user that invoked this call so we can determine the GPG home dir later
    if [ $SUDO_USER ]; then REAL_USER="$SUDO_USER"; else REAL_USER="$(whoami)"; fi
    # export GNUPGHOME=/home/$REAL_USER/.gnupg/
    pushd iso
    for i in $(find . -maxdepth 1 -type f -name '*.iso' -printf '%f\n')
    do
        RAW_NAME="$(basename $i -s)"
        rm -rf $RAW_NAME.sig
        GNUPGHOME=/home/$REAL_USER/.gnupg/ gpg --output $RAW_NAME.sig --sign --local-user $REAL_USER --default-key {{gpg_key}} $i
    done
    popd

sign-all variant=default_variant gpg_key="":
    #!/bin/bash
    set -euxo pipefail

    just sign-repo {{variant}} {{gpg_key}}
    just sign-iso {{variant}} {{gpg_key}}

export-release variant=default_variant gpg_key="":
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    ref="$(rpm-ostree compose tree --print-only --repo=repo fedora-{{variant}}.yaml | jq -r '.ref')"
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
    pushd release
    # Set to best compression since it does not change anything in the result since most of the parts are already compressed anyway
    zip -r -q -9 ${version}.zip ${version}
    popd

# Compose a specific variant of Fedora (defaults to Silverblue)
compose variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "photon-pony")
            variant_pretty="PhotonPonyOS"
            ;;
        "photon-pony-base")
            variant_pretty="PhotonPonyOSBase"
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

    ./ci/validate > /dev/null || (echo "Failed manifest validation" && exit 1)

    just prep

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    # TODO: Pull latest build for the current release
    # ostree pull ...

    version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"

    echo "Composing ${variant_pretty} ${version}.${buildid} ..."
    # To debug with gdb, use: gdb --args ...

    ARGS="--repo=repo --layer-repo=repo --cachedir=cache"
    if [[ {{unified_core}} == "true" ]]; then
        ARGS+=" --unified-core"
    else
        ARGS+=" --workdir=tmp"
        rm -rf ./tmp
        mkdir -p tmp
        export RPM_OSTREE_I_KNOW_NON_UNIFIED_CORE_IS_DEPRECATED=1
        # TODO: Check if this is still needed
        export SYSTEMD_OFFLINE=1
    fi
    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=" --force-nocache"
    fi
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        SUDO="sudo rpm-ostree"
    fi

    ${CMD} compose tree ${ARGS} \
        --add-metadata-string="version=${variant_pretty} ${version}.${buildid}" \
        "fedora-${variant}.yaml" \
            |& tee "logs/${variant}_${version}_${buildid}.${timestamp}.log"

    if [[ ${EUID} -ne 0 ]]; then
        if [[ {{unified_core}} == "false" ]]; then
            sudo chown --recursive "$(id --user --name):$(id --group --name)" tmp
        fi
        sudo chown --recursive "$(id --user --name):$(id --group --name)" repo cache
    fi

    ostree summary --repo=repo --update
    just fix-ownership

# Compose an OCI image
compose-image variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "photon-pony")
            variant_pretty="PhotonPonyOS"
            ;;
        "photon-pony-base")
            variant_pretty="PhotonPonyOSBase"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    # on_failure() {
    #     just archive {{variant}} repo
    # }
    # trap "on_failure" ERR

    ./ci/validate > /dev/null || (echo "Failed manifest validation" && exit 1)

    just prep

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    # TODO: Pull latest build for the current release
    # ostree pull ...

    version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"

    echo "Composing ${variant_pretty} ${version}.${buildid} ..."
    # To debug with gdb, use: gdb --args ...

    ARGS="--cachedir=cache --initialize"
    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=" --force-nocache"
    fi
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        SUDO="sudo rpm-ostree"
    fi

    ${CMD} compose image ${ARGS} \
         --label="quay.expires-after=4w" \
        "fedora-${variant}.yaml" \
        "fedora-${variant}.ociarchive" \
            |& tee "logs/${variant}_${version}_${buildid}.${timestamp}.log"

# Last steps from the compose recipe that can easily fail when the sudo timeout is reached
compose-finalise:
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

# Serve the generated commit for testing
serve:
    # See https://github.com/TheWaWaR/simple-http-server
    simple-http-server --index --ip 192.168.122.1 --port 8000 --silent

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
        "photon-pony")
            variant_pretty="PhotonPonyOS"
            volid_sub="PPOS"
            ;;
        "photon-pony-base")
            variant_pretty="PhotonPonyOSBase"
            volid_sub="PPOSBase"
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

    version_number="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"
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
        --add-template-var=ostree_oskey=fedora-${version_number}-primary \
        --add-template-var=ostree_contenturl=mirrorlist=https://ostree.fedoraproject.org/mirrorlist \
        --add-template-var=ostree_install_ref=fedora/${version}/${arch}/${variant} \
        --add-template-var=ostree_update_ref=fedora/${version}/${arch}/${variant} \
        ${pwd}/iso/linux
    
    mv iso/linux/images/boot.iso iso/Fedora-${volid_sub}-ostree-${arch}-${version_pretty}-${buildid}.iso
    just kickstart iso/Fedora-${volid_sub}-ostree-${arch}-${version_pretty}-${buildid}.iso iso/KS-Fedora-${volid_sub}-ostree-${arch}-${version_pretty}-${buildid}.iso
    just fix-ownership

kickstart inputIso outputIso:
    #!/bin/bash
    set -euxo pipefail
    mkksiso $(pwd)/ppos.ks {{inputIso}} {{outputIso}}

upload-container variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "photon-pony")
            variant_pretty="PhotonPonyOS"
            ;;
        "photon-pony-base")
            variant_pretty="PhotonPonyOSBase"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping artifact archiving: Not in CI"
        exit 0
    fi
    if [[ "${CI}" != "true" ]]; then
        echo "Skipping artifact archiving: Not in CI"
        exit 0
    fi

    version=""
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version="rawhide"
    else
        version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"
    fi

    image="quay.io/fedora-ostree-desktops/${variant}"
    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    git_commit=""
    if [[ -n "${CI_COMMIT_SHORT_SHA}" ]]; then
        git_commit="${CI_COMMIT_SHORT_SHA}"
    else
        git_commit="$(git rev-parse --short HEAD)"
    fi

    skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" quay.io
    # Copy fully versioned tag (major version, build date/id, git commit)
    skopeo copy --retry-times 3 "oci-archive:fedora-${variant}.ociarchive" "docker://${image}:${version}.${buildid}.${git_commit}"
    # Update "un-versioned" tag (only major version)
    skopeo copy --retry-times 3 "docker://${image}:${version}.${buildid}.${git_commit}" "docker://${image}:${version}"
    if [[ "${variant}" == "kinoite-nightly" ]] || [[ "${variant}" == "kinoite-beta" ]]; then
        # Update latest tag for kinoite-nightly only
        skopeo copy --retry-times 3 "docker://${image}:${version}.${buildid}.${git_commit}" "docker://${image}:latest"
    fi
    just fix-ownership

# Make a container image with the artifacts
archive variant=default_variant kind="repo":
    #!/bin/bash
    set -euxo pipefail

    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping artifact archiving: Not in CI"
        exit 0
    fi
    if [[ "${CI}" == "true" ]]; then
        rm -rf cache
    fi

    variant={{variant}}
    case "${variant}" in
        "photon-pony")
            variant_pretty="PhotonPonyOS"
            ;;
        "photon-pony-base")
            variant_pretty="PhotonPonyOSBase"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    kind={{kind}}
    case "${kind}" in
        "repo")
            echo "Archiving repo"
            ;;
        "iso")
            echo "Archiving iso"
            ;;
        "*")
            echo "Unknown kind"
            exit 1
            ;;
    esac

    version=""
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version="rawhide"
    else
        version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"
    fi

    if [[ "${kind}" == "repo" ]]; then
        tar --create --file repo.tar.zst --zstd repo
        if [[ "${CI}" == "true" ]]; then
            rm -rf repo
        fi
    fi
    if [[ "${kind}" == "iso" ]]; then
        tar --create --file iso.tar.zst --zstd iso
        if [[ "${CI}" == "true" ]]; then
            rm -rf iso
        fi
    fi

    container="$(buildah from scratch)"
    if [[ "${kind}" == "repo" ]]; then
        buildah copy "${container}" repo.tar.zst /
    fi
    if [[ "${kind}" == "iso" ]]; then
        buildah copy "${container}" iso.tar.zst /
    fi
    buildah config --label "quay.expires-after=2w" "${container}"
    commit="$(buildah commit ${container})"

    image="quay.io/fedora-ostree-desktops/${variant}"
    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    git_commit=""
    if [[ -n "${CI_COMMIT_SHORT_SHA}" ]]; then
        git_commit="${CI_COMMIT_SHORT_SHA}"
    else
        git_commit="$(git rev-parse --short HEAD)"
    fi

    buildah login -u "${CI_REGISTRY_USER}" -p "${CI_REGISTRY_PASSWORD}" quay.io
    buildah push "${commit}" "docker://${image}:${version}.${buildid}.${git_commit}.${kind}"
    just fix-ownership

fix-ownership:
    #!/bin/bash
    set -euxo pipefail

    if [ $SUDO_USER ]; then user="$SUDO_USER"; else user="$(whoami)"; fi
    chown -R ${user}:${user} .
