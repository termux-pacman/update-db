#!/bin/bash

# Import func
source ./aws-cli-action/func.sh
repo="$1"
bucket="termux-pacman.us"
arch="$2"
upload=false
get_db_log=true

# Func for getting dbs
get_db() {
  if $get_db_log; then
    for format in db files; do
      get-object $repo/$arch/$repo.$format $repo.$format.tar.gz
      get-object $repo/$arch/$repo.$format.sig $repo.$format.tar.gz.sig
      if ! $(gpg --verify $repo.$format.tar.gz.sig $repo.$format.tar.gz); then
        echo "Eroor: with $repo.$format.tar.gz.sig"
        exit 1
      fi
    done
    get_db_log=false
  fi
}

# Get list of files
files=$(aws s3api list-objects --bucket "${bucket}" --prefix "${repo}/${arch}/" | jq -r '.Contents[].Key')

# Delete packages and sig of packages + creare new sigs
name_fdp="deleted_termux-${repo}_packages.txt"
file_dp=$(echo "$files" | grep "pkgs/$name_fdp")
if [[ -n $file_dp ]]; then
  get-object $file_dp $name_fdp
  get-object $file_dp.sig $name_fdp.sig
  if $(gpg --verify $name_fdp.sig $name_fdp); then
    get_db
    for i in $(cat $name_fdp); do
      ./repo-remove.sh --verify --sign --key $KEY_GPG $repo.db.tar.gz $i || true
      del-all-pkg $(echo $i | sed 's/+/0/g')
    done
    aws-rm $file_dp
    aws-rm $file_dp.sig
    upload=true
  else
    echo "Attention: package removal failed, sig did not match."
  fi
  rm $name_fdp*
fi

# Update packages and create new sigs
files_pkg=$(echo "$files" | grep "/pkgs/" | grep "\.pkg\.")
if [[ -n $files_pkg ]]; then
  for i in $files_pkg; do
    if [[ $i != *".pkg."*".sig" ]]; then
      i2=$(echo ${i##*/} | sed 's/+/0/g')
      get-object $i $i2
      get-object $i.sig $i2.sig
      if $(gpg --verify $i2.sig $i2); then
        get_db
        rm $i2.sig
        aws-rm $i.sig
        gpg --no-tty --pinentry-mode=loopback --passphrase $PW_GPG --detach-sign --use-agent -u $KEY_GPG --no-armor "$i2"
        ./repo-add.sh --verify --sign --key $KEY_GPG $repo.db.tar.gz $i2
        del-old-pkg $i2
        aws-mv $i $repo/$arch/$i2
        put-object $repo/$arch/$i2.sig $i2.sig
        upload=true
      else
        echo "Attention: failed to update package '${i}', sig did not match."
      fi
      rm $i2*
    fi
  done
fi

# Upload db and sig of db
if $upload; then
  for i in db files; do
    put-object $repo/$arch/$repo.$i $repo.$i.tar.gz
    put-object $repo/$arch/$repo.$i.sig $repo.$i.tar.gz.sig
    rm $repo.$i*
  done
fi
