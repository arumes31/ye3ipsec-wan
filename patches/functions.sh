#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2148,SC1083,SC2001,SC2076,SC2005,SC1090,SC2053,SC2153,SC2046

function f_replace(){
	
	if [[ "$#" -eq 4 ]] ; then
	
		command=$1
		file=$2
		search=$3
		replacement=$4
		
		if [[ -f $file ]] && [[ -f $search ]] && [[ -f $replacement ]] ; then
		
			if [[ $command == "xxd" ]]; then
			
				file_hex=$(xxd -p $file | tr -d '\n')
				search_hex=$(xxd -p $search | tr -d '\n')
				replacement_hex=$(xxd -p $replacement | tr -d '\n')
				echo $(echo $file_hex | sed -e "s/$search_hex/$replacement_hex/g") | xxd -r -p > $file
				
			elif [[ $command == "printf" ]]; then
			
				file_content=$(cat $file)
				search_content=$(cat $search)
				replacement_content=$(cat $replacement)
				printf '%s\n' "${file_content/"$search_content"/"$replacement_content"}" > $file

			else
			
				echo "patch :: f_replace :: error :: unknown command"
				
			fi
			
		else
		
			echo "patch :: f_replace :: error :: file missing"
			
		fi
	
	else
		
		echo "patch :: f_replace :: error :: invalid argument number"
	
	fi
	
}
