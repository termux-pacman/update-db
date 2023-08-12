#!/bin/bash

set -e

# Import func
source ./aws-cli-action/func.sh
repo="$1"
bucket="termux-pacman.us"
arch="$2"
upload=false

ls_files_s3() {
	local request=$(aws s3api list-objects --bucket "${1}" --prefix "${2}")
	if [[ $(echo "$request" | jq -r '."Contents"') != "null" ]]; then
		echo "$request" | jq -r '.Contents[].Key'
	fi
}

# Get and check dbs
for format in db files; do
  get-object $repo/$arch/$repo.$format $repo.$format.tar.gz
  get-object $repo/$arch/$repo.$format.sig $repo.$format.tar.gz.sig
  if ! $(gpg --verify $repo.$format.tar.gz.sig $repo.$format.tar.gz); then
    echo "Eroor: with $repo.$format.tar.gz.sig"
    exit 1
  fi
done

# Get list of files
files=$(ls_files_s3 "${bucket}" "${repo}/${arch}/")
sfpu_files=$(ls_files_s3 "${SFPU}" "${repo}/${arch}/")

# Delete packages and sig of packages
case $repo in
  main|root|x11) name_fdp="deleted_termux-${repo}_packages.txt";;
  *) name_fdp="deleted_${repo}_packages.txt";;
esac
files_dp=$(echo "$sfpu_files" | grep "$name_fdp" | head -1)
if [[ -n $files_dp ]]; then
  for i in $files_dp; do
    if [[ $i != *"$name_fdp"*".sig" ]]; then
      bucket="$SFPU" get-object $i $name_fdp
      bucket="$SFPU" get-object $i.sig $name_fdp.sig
      if $(gpg --verify $name_fdp.sig $name_fdp); then
        for j in $(cat $name_fdp); do
          for z in "" "-static"; do
            repo-remove $repo.db.tar.gz "${j}${z}" || true
            del-all-pkg $(echo "${j}${z}" | sed 's/+/0/g')
          done
        done
        #bucket="$SFPU" aws-rm $i
        #bucket="$SFPU" aws-rm $i.sig
        upload=true
      else
        echo "Attention: package removal failed, sig did not match."
      fi
      rm $name_fdp*
    fi
  done
fi

# Update packages and create new sigs of packages
files_pkg=$(echo "$sfpu_files" | grep "\.pkg\.") || true
if [[ -n $files_pkg ]]; then
  for i in $files_pkg; do
    if [[ $i != *".pkg."*".sig" ]]; then
      i2=$(echo ${i##*/} | sed 's/+/0/g')
      bucket="$SFPU" get-object $i $i2
      bucket="$SFPU" get-object $i.sig $i2.sig
      if $(gpg --verify $i2.sig $i2); then
        rm $i2.sig
        #bucket="$SFPU" aws-rm $i
        #bucket="$SFPU" aws-rm $i.sig
        gpg --no-tty --pinentry-mode=loopback --passphrase $PW_GPG --detach-sign --use-agent -u $KEY_GPG --no-armor "$i2"
        repo-add $repo.db.tar.gz $i2
        del-old-pkg $i2
        name_pkg=$(get_name $i)
        if ! $(echo "$name_pkg" | grep -q '\-static'); then
          repo-remove $repo.db.tar.gz "${name_pkg}-static" || true
          del-all-pkg "${name_pkg}-static"
        fi
        put-object $repo/$arch/$i2 $i2
        put-object $repo/$arch/$i2.sig $i2.sig
        upload=true
      else
        echo "Attention: failed to update package '${i}', sig did not match."
      fi
      rm $i2*
    fi
  done
fi

if $upload; then
  # Create json of repo
  python mrj.py $repo
  mv $repo.json $repo.json.tar.gz

  # Upload db, sig of db and json of repo
  for i in db files json; do
    rm $repo.$i.tar.gz.sig || true
    gpg --batch --pinentry-mode=loopback --passphrase $PW_GPG --detach-sign --use-agent -u $KEY_GPG --no-armor "$repo.$i.tar.gz"
    put-object $repo/$arch/$repo.$i $repo.$i.tar.gz
    put-object $repo/$arch/$repo.$i.sig $repo.$i.tar.gz.sig
  done

  # Removing files from SFPU
  for i in $(echo "$sfpu_files" | awk -F '/' '{printf $3 " "}'); do
    bucket="$SFPU" aws-rm $repo/$arch/$i
  done
fi
