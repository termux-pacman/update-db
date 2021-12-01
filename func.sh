#!/bin/bash

get_name() {
	local name=""
	local file_sp=(${1//-/ })
	for k in $(seq 0 $((${#file_sp[*]}-4))); do
		if [ -z $name ]; then
			name="${file_sp[k]}"
		else
			name+="-${file_sp[k]}"
		fi
	done
	echo $name
}

get-object() {
	aws s3api get-object --bucket $bucket --key $1 $2 >/dev/null 2>&1
}

put-object() {
	aws s3api put-object --bucket $bucket --key $1 --body $2 >/dev/null 2>&1
}

aws-ls() {
	for k in $(aws s3 ls s3://$bucket/$1 --recursive | awk '{print $4}'); do
          echo $k
        done
}

aws-mv() {
	aws s3 mv s3://$bucket/$1 s3://$bucket/$2 >/dev/null 2>&1
}

aws-rm() {
	aws s3 rm s3://$bucket/$1 >/dev/null 2>&1
}
