#!/usr/bin/env bash
# Builds and pushes every platform image of images/platform-images.json as a candidate: the
# dated tag <tag>-<stamp>, nothing else (publish-platform-images.yml moves -rc afterwards). In
# the list's order, each image on its base of this same run, by digest, so the images of one
# release share one base: an image with "base": "headless" gets the build argument
# HEADLESS=<namespace>/headless@<digest>.
#
#   images/build.sh <out.json>
#
# Writes <out.json>: {"<name>": "<namespace>/<name>:<tag>-<stamp>@<digest>", …}, in the list's
# order. Reads from the environment, as the workflow sets them:
#   STAMP            the dated tag's suffix (yyyymmdd-<sha7>-<run>)
#   UBUNTU_SNAPSHOT  the archive snapshot of the run's day (yyyymmddT000000Z)
#   IMAGE_CREATED    the same moment in RFC 3339
#   IMAGE_REVISION   the commit
# Needs docker buildx, logged in to Docker Hub, and jq. Release process: images/README.md (Releases).
set -euo pipefail

out=${1:?usage: images/build.sh <out.json>}
: "${STAMP:?}" "${UBUNTU_SNAPSHOT?}" "${IMAGE_CREATED?}" "${IMAGE_REVISION?}"
here=$(cd "$(dirname "$0")" && pwd)
list="$here/platform-images.json"
namespace=$(jq -er .namespace "$list")
tag=$(jq -er .tag "$list")
meta=$(mktemp)
trap 'rm -f "$meta"' EXIT

built='{}'
while read -r name base; do
	args=(
		--build-arg "UBUNTU_SNAPSHOT=$UBUNTU_SNAPSHOT"
		--build-arg "IMAGE_VERSION=$tag-$STAMP"
		--build-arg "IMAGE_CREATED=$IMAGE_CREATED"
		--build-arg "IMAGE_REVISION=$IMAGE_REVISION"
	)
	if [ -n "$base" ]; then
		from=$(jq -r --arg base "$base" '.[$base] // empty' <<<"$built")
		[ -n "$from" ] || { echo "::error::$name is built on $base, which the list does not build before it" >&2; exit 1; }
		# HEADLESS=ghostdockhq/headless@sha256:…: the digest only, as the Dockerfile's FROM takes it.
		args+=(--build-arg "$(tr 'a-z-' 'A-Z_' <<<"$base")=$namespace/$base@${from##*@}")
	fi
	ref="$namespace/$name:$tag-$STAMP"
	echo "==> $ref${base:+ on $base}"
	docker buildx build \
		--file "$here/$name/Dockerfile" \
		--platform linux/amd64 \
		--pull --no-cache --push \
		--metadata-file "$meta" \
		--tag "$ref" \
		"${args[@]}" \
		"$here"
	digest=$(jq -er '."containerimage.digest"' "$meta")
	built=$(jq --arg name "$name" --arg ref "$ref@$digest" '. + {($name): $ref}' <<<"$built")
done < <(jq -r '.images[] | "\(.name) \(.base // "")"' "$list")

printf '%s\n' "$built" >"$out"
