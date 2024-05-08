#!/bin/bash

set -e

# Import func
source ./aws-cli-action/func.sh
repo="$1"
bucket="termux-pacman.us"
arch="$2"
upload=false
oldpkgs="oldpkgs.db"
update_oldpkgs=false

ls_files_s3() {
	local request=$(aws s3api list-objects --bucket "${1}" --prefix "${2}")
	if [[ $(jq -r '."Contents"' <<< "$request") != "null" ]]; then
		jq -r '.Contents[].Key' <<< "$request"
	fi
}

del-old-pkg() {
	local name_pkg=$(get_name $1)
	for _pkg_f_del_old_pkg in $(grep $name_pkg <<< "$files"); do
		if [[ ${_pkg_f_del_old_pkg} != *".pkg."*".sig" && $1 != $(sed 's/+/0/g' <<< ${_pkg_f_del_old_pkg##*/}) && \
			$name_pkg = $(get_name ${_pkg_f_del_old_pkg##*/}) ]] && \
			! grep -q "^${_pkg_f_del_old_pkg}===" ${oldpkgs}; then
			echo "${_pkg_f_del_old_pkg}===$(date +%s)" >> ${oldpkgs}
		fi
	done
	update_oldpkgs=true
}

del-all-pkg() {
	for _pkg_f_del_all_pkg in $(grep $1 <<< "$files"); do
		if [[ ${_pkg_f_del_all_pkg} != *".pkg."*".sig" && $1 = $(get_name ${_pkg_f_del_all_pkg##*/}) ]] && \
			! grep -q "^${_pkg_f_del_all_pkg}===" ${oldpkgs}; then
			echo "${_pkg_f_del_all_pkg}===$(date +%s)" >> ${oldpkgs}
		fi
	done
	update_oldpkgs=true
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

# Delete old packages
bucket="$SFPU" get-object system-files/$repo/$arch/$oldpkgs $oldpkgs
for i in $(cat $oldpkgs); do
  if [[ $(( ( ($(date +%s) - ${i#*===}) / 3600 ) > 12 )) = 1 ]]; then
    for j in $(grep ${i%%===*} <<< "$files"); do
      aws-rm $j
    done
    sed -i "\|^${i}$|d" $oldpkgs
    update_oldpkgs=true
  fi
done

# Delete packages and sig of packages
case $repo in
  main|root|x11) name_fdp="deleted_termux-${repo}_packages.txt";;
  *) name_fdp="deleted_${repo}_packages.txt";;
esac
files_dp=$(grep "$name_fdp" <<< "$sfpu_files" | head -1)
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
        upload=true
      else
        echo "Attention: package removal failed, sig did not match."
      fi
      rm $name_fdp*
    fi
  done
fi

# Update packages and create new sigs of packages
files_pkg=$(grep "\.pkg\." <<< "$sfpu_files") || true
if [[ -n $files_pkg ]]; then
  for i in $files_pkg; do
    if [[ $i != *".pkg."*".sig" ]]; then
      i2=$(sed 's/+/0/g' <<< ${i##*/})
      bucket="$SFPU" get-object $i $i2
      bucket="$SFPU" get-object $i.sig $i2.sig
      if $(gpg --verify $i2.sig $i2); then
        rm $i2.sig
        gpg --no-tty --pinentry-mode=loopback --passphrase $PW_GPG --detach-sign --use-agent -u $KEY_GPG --no-armor "$i2"
        repo-add $repo.db.tar.gz $i2
        del-old-pkg $i2
        name_pkg=$(get_name $i2)
        if ! $(grep -q '\-static' <<< "$name_pkg"); then
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

# Upload list old pkgs
if $update_oldpkgs; then
  bucket="$SFPU" put-object system-files/$repo/$arch/$oldpkgs $oldpkgs
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
  for i in $sfpu_files; do
    bucket="$SFPU" aws-rm $i
  done
fi
