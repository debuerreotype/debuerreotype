#!/usr/bin/env bash
set -Eeuo pipefail

# create https://github.com/opencontainers/image-spec/blob/v1.0.1/image-layout.md (+ Docker's "manifest.json") from the output of "debian.sh"
# the resulting file is suitable for "ctr image import" or "docker load"

source "$DEBUERREOTYPE_DIRECTORY/scripts/.constants.sh" \
	--flags 'meta:' \
	-- \
	'<target-file.tar> <source-directory>' \
	'out/oci-unstable-slim.tar out/20210511/amd64/unstable/slim'

eval "$dgetopt"
meta=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--meta) meta="$1"; shift ;;
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

target="${1:-}"; shift || eusage 'missing target-file' # "something.tar"
sourceDir="${1:-}"; shift || eusage 'missing source-directory' # "out/YYYYMMDD/ARCH/SUITE{,/slim}"

target="$(readlink -vf "$target")"
if [ -n "$meta" ]; then
	meta="$(readlink -vf "$meta")"
fi
sourceDir="$(readlink -ve "$sourceDir")"

tempDir="$(mktemp -d)"
trap "$(printf 'rm -rf %q' "$tempDir")" EXIT

mkdir -p "$tempDir/oci/blobs/sha256"
jq --null-input --compact-output '{ imageLayoutVersion: "1.0.0" }' > "$tempDir/oci/oci-layout"

version="$(< "$sourceDir/rootfs.debuerreotype-version")"
epoch="$(< "$sourceDir/rootfs.debuerreotype-epoch")"
iso8601="$(date --date="@$epoch" '+%Y-%m-%dT%H:%M:%SZ')"
export version epoch iso8601

suite="$(< "$sourceDir/rootfs.apt-dist")"
export suite

variant="$(< "$sourceDir/rootfs.debuerreotype-variant")"

dpkgArch="$(< "$sourceDir/rootfs.dpkg-arch")"

unset goArch
case "$dpkgArch" in
	amd64 | arm64 | riscv64 | s390x) goArch="$dpkgArch" ;;
	armhf | armel | arm) goArch='arm' ;;
	i386) goArch='386' ;;
	mips64el | ppc64el) goArch="${dpkgArch%el}le" ;;
	*) echo >&2 "error: unknown dpkg architecture: '$dpkgArch'"; exit 1 ;;
esac

# https://wiki.debian.org/ArchitectureSpecificsMemo#Architecture_baselines
# https://github.com/opencontainers/image-spec/pull/1172
ociVariant=
case "$goArch" in
	arm64) ociVariant='v8' ;; # https://wiki.debian.org/ArchitectureSpecificsMemo#arm64
	arm)
		case "$dpkgArch" in
			armel) ociVariant='v5' ;; # https://wiki.debian.org/ArchitectureSpecificsMemo#armel
			armhf)
				if grep -qi raspbian "$sourceDir/rootfs.os-release"; then
					ociVariant='v6' # this is why Raspbian exists in the first place 😅
				else
					ociVariant='v7' # https://wiki.debian.org/ArchitectureSpecificsMemo#armhf
				fi
				;;
		esac
		;;
esac

unset bashbrewArch
case "$goArch" in
	386) bashbrewArch='i386' ;;
	amd64 | mips64le | ppc64le | riscv64 | s390x) bashbrewArch="$goArch" ;;
	arm) bashbrewArch="${goArch}32${ociVariant}" ;;
	arm64) bashbrewArch="${goArch}v8" ;;
	*) echo >&2 "error: unknown Go architecture: '$goArch'"; exit 1 ;;
esac

export dpkgArch goArch ociVariant bashbrewArch

osID="$(id="$(grep -E '^ID=' "$sourceDir/rootfs.os-release")" && eval "$id" && echo "${ID:-}")" || : # "debian", "raspbian", "ubuntu", etc
: "${osID:=debian}" # if for some reason the above fails, fall back to "debian"

echo >&2 "processing $osID '$suite'${variant:+", variant '$variant'"}, architecture '$dpkgArch' ('$bashbrewArch')"

_sha256() {
	sha256sum "$@" | cut -d' ' -f1
}

echo >&2 "decompressing rootfs (xz) ..."

xz --decompress --threads=0 --stdout "$sourceDir/rootfs.tar.xz" > "$tempDir/rootfs.tar"
diffId="$(_sha256 "$tempDir/rootfs.tar")"
export diffId="sha256:$diffId"

echo >&2 "recompressing rootfs (gzip) ..."

pigz --best --no-time "$tempDir/rootfs.tar"
rootfsSize="$(stat --format='%s' "$tempDir/rootfs.tar.gz")"
rootfsSha256="$(_sha256 "$tempDir/rootfs.tar.gz")"
export rootfsSize rootfsSha256
mv "$tempDir/rootfs.tar.gz" "$tempDir/oci/blobs/rootfs.tar.gz"
ln -sfT ../rootfs.tar.gz "$tempDir/oci/blobs/sha256/$rootfsSha256"

script='debian.sh'
if [ -x "$DEBUERREOTYPE_DIRECTORY/examples/$osID.sh" ]; then
	script="$osID.sh"
fi
export script

echo >&2 "generating config ..."

# https://github.com/opencontainers/image-spec/blob/v1.0.1/config.md
jq --null-input --compact-output '
	{
		config: {
			Env: [ "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" ],
			Entrypoint: [],
			Cmd: [ "bash" ],
		},
		created: env.iso8601,
		history: [
			{
				created: env.iso8601,
				created_by: (
					"# " + env.script
					+ if env.script != "raspbian.sh" then
						" --arch " + (env.dpkgArch | @sh)
					else "" end
					+ " out/ "
					+ (env.suite | @sh)
					+ if env.script == "debian.sh" then
						" "
					else
						" # "
					end
					+ ("@" + env.epoch | @sh)
				),
				comment: ( "debuerreotype " + env.version ),
			}
		],
		rootfs: {
			type: "layers",
			diff_ids: [ env.diffId ],
		},
		os: "linux",
		architecture: env.goArch,
	}
	| if env.ociVariant != "" then
		.variant = env.ociVariant
	else . end
' > "$tempDir/config.json"
configSize="$(stat --format='%s' "$tempDir/config.json")"
configSha256="$(_sha256 "$tempDir/config.json")"
configData="$(base64 -w0 "$tempDir/config.json")" # so we can embed it in the descriptor 👀
export configSize configSha256 configData
mv "$tempDir/config.json" "$tempDir/oci/blobs/image-config.json"
ln -sfT ../image-config.json "$tempDir/oci/blobs/sha256/$configSha256"

# https://github.com/opencontainers/image-spec/blob/v1.0.1/manifest.md
jq --null-input --compact-output '
	{
		schemaVersion: 2,
		mediaType: "application/vnd.oci.image.manifest.v1+json",
		config: {
			mediaType: "application/vnd.oci.image.config.v1+json",
			digest: ( "sha256:" + env.configSha256 ),
			size: (env.configSize | tonumber),
			data: env.configData,
		},
		layers: [
			{
				mediaType: "application/vnd.oci.image.layer.v1.tar+gzip",
				digest: ( "sha256:" + env.rootfsSha256 ),
				size: (env.rootfsSize | tonumber),
			}
		],
		# TODO add some interesting annotations here
	}
' > "$tempDir/manifest.json"
manifestSize="$(stat --format='%s' "$tempDir/manifest.json")"
manifestSha256="$(_sha256 "$tempDir/manifest.json")"
manifestData="$(base64 -w0 "$tempDir/manifest.json")" # so we can embed it in the descriptor 👀
export manifestSize manifestSha256 manifestData
mv "$tempDir/manifest.json" "$tempDir/oci/blobs/image-manifest.json"
ln -sfT ../image-manifest.json "$tempDir/oci/blobs/sha256/$manifestSha256"

export repo="$bashbrewArch/$osID" # "amd64/debian", "arm32v6/raspbian", etc.
export tag="$suite${variant:+-$variant}" # "buster", "buster-slim", etc.
export image="$repo:$tag"

# https://github.com/opencontainers/image-spec/blob/v1.0.1/image-index.md
platform="$(jq --compact-output 'with_entries(select(.key == ([ "os", "architecture", "variant" ][])))' "$tempDir/oci/blobs/sha256/$configSha256")"
jq --null-input --compact-output --argjson platform "$platform" '
	{
		schemaVersion: 2,
		mediaType: "application/vnd.oci.image.index.v1+json",
		manifests: [
			{
				mediaType: "application/vnd.oci.image.manifest.v1+json",
				digest: ( "sha256:" + env.manifestSha256 ),
				size: (env.manifestSize | tonumber),
				platform: $platform,
				annotations: {
					"io.containerd.image.name": env.image,
					"org.opencontainers.image.ref.name": env.image,
				},
				data: env.manifestData,
			}
		],
	}
' > "$tempDir/oci/index.json"

# Docker's "manifest.json" so that we can "docker load" the result of this script too
jq --null-input --compact-output '
	[
		{
			Config: ( "blobs/sha256/" + env.configSha256 ),
			Layers: [ "blobs/sha256/" + env.rootfsSha256 ],
			RepoTags: [ env.image ],
		}
	]
' > "$tempDir/oci/manifest.json"

echo >&2 "fixing timestamps ..."

find "$tempDir/oci" \
	-newermt "@$epoch" \
	-exec touch --no-dereference --date="@$epoch" '{}' +

if [ -d "$target" ]; then
	# this is an undocumented feature -- if you run the script with an existing directory, it will assume that directory must be where you want the OCI bundle dumped
	echo >&2 "copying ($target) ..."
	rsync -a --delete-after "$tempDir/oci/" "$target/"
else
	echo >&2 "generating tarball ($target) ..."

	tar --create \
		--auto-compress \
		--directory "$tempDir/oci" \
		--file "$target" \
		--numeric-owner --owner 1000:1000 \
		--sort name \
		.
	touch --no-dereference --date="@$epoch" "$target"
fi

jq --null-input --tab --argjson platform "$platform" '
	{
		image: env.image,
		repo: env.repo,
		tag: env.tag,
		id: ( "sha256:" + env.configSha256 ),
		digest: ( "sha256:" + env.manifestSha256 ),
		platform: $platform,
	}
' > "$tempDir/meta.json"
touch --no-dereference --date="@$epoch" "$tempDir/meta.json"
if [ -n "$meta" ]; then
	cp -a "$tempDir/meta.json" "$meta"
fi

jq >&2 . "$tempDir/meta.json"
