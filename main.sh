#!/bin/bash

# Import func
source ./aws-cli-action/func.sh
repo="$1"
bucket="termux-pacman.us"
arch="$2"
upload=false

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
files=$(aws s3api list-objects --bucket "${bucket}" --prefix "${repo}/${arch}/" | jq -r '.Contents[].Key')
sfpu_files=$(aws s3api list-objects --bucket "${SFPU}" --prefix "${repo}/${arch}/" | jq -r '.Contents[].Key')

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
        bucket="$SFPU" aws-rm $file_dp
        bucket="$SFPU" aws-rm $file_dp.sig
        upload=true
      else
        echo "Attention: package removal failed, sig did not match."
      fi
      rm $name_fdp*
    fi
  done
fi

# Update packages and create new sigs of packages
files_pkg=$(echo "$sfpu_files" | grep "\.pkg\.")
if [[ -n $files_pkg ]]; then
  for i in $files_pkg; do
    if [[ $i != *".pkg."*".sig" ]]; then
      i2=$(echo ${i##*/} | sed 's/+/0/g')
      bucket="$SFPU" get-object $i $i2
      bucket="$SFPU" get-object $i.sig $i2.sig
      if $(gpg --verify $i2.sig $i2); then
        rm $i2.sig
        bucket="$SFPU" aws-rm $i
        bucket="$SFPU" aws-rm $i.sig
        gpg --no-tty --pinentry-mode=loopback --passphrase $PW_GPG --detach-sign --use-agent -u $KEY_GPG --no-armor "$i2"
        repo-add $repo.db.tar.gz $i2
        del-old-pkg $i2
        name_pkg = $(get_name $i)
        if ! $(echo "$name_pkg" | grep -q '\-static'); then
          repo-remove $repo.db.tar.gz $name_pkg || true
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
  # Update json of repo
  file_json=$(echo "$files" | grep "${repo}.json" | head -1)
  if [[ -n $file_json ]]; then
    get-object $file_json $repo.json
    get-object $file_json.sig $repo.json.sig
    if ! $(gpg --verify $repo.json.sig $repo.json); then
      rm $repo.json
      echo "Attention: ${repo}.json was removed because sig didn't match."
    fi
  fi
  python mrj.py $repo
  mv $repo.json $repo.json.tar.gz

  # Upload db, sig of db and json of repo
  for i in db files json; do
    rm $repo.$i.tar.gz.sig
    gpg --batch --pinentry-mode=loopback --passphrase $PW_GPG --detach-sign --use-agent -u $KEY_GPG --no-armor "$repo.$i.tar.gz"
    put-object $repo/$arch/$repo.$i $repo.$i.tar.gz
    put-object $repo/$arch/$repo.$i.sig $repo.$i.tar.gz.sig
    rm $repo.$i*
  done
fi
