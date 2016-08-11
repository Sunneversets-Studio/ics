#!/bin/bash

source "names.sh";

(
	declare -A regexes;
	echo "package ics";
	echo;
	echo "// File automatically generated with ./genParams.sh";
	echo;
	echo "import (";
	echo "	\"errors\"";
	echo "	\"regexp\"";
	echo "	\"strings\"";
	echo;
	echo "	\"github.com/MJKWoolnough/parser\"";
	echo ")";
	echo;
	{
		while read line; do
			keyword="$(echo "$line" | cut -d'=' -f1)";
			type="$(getName "$keyword")";
			values="$(echo "$line" | cut -d'=' -f2)";

			echo -n "type $type ";

			declare multiple=false;
			declare freeChoice=false;
			declare doubleQuote=false;
			declare regex="";
			declare vType="";
			declare string=false;
			declare -a choices=();
			fc="${values:0:1}";
			if [ "$fc" = "*" ]; then
				echo -n "[]";
				multiple=true
				values="${values:1}";
				fc="${values:0:1}";
			fi;
			if [ "$fc" = "?" ]; then
				freeChoice=true
				values="${values:1}";
				fc="${values:0:1}";
			fi;
			if [ "$fc" = '"' ]; then
				doubleQuote=true;
				values="${values:1}";
				fc="${values:0:1}";
				string=true;
			elif [ "$fc" = "'" ]; then
				values="${values:1}";
				string=true;
				fc="${values:0:1}";
			elif [ "$fc" = "~" ]; then
				regex="${values:1}";
				string=true;
				values="${values:1}";
				fc="${values:0:1}";
			fi;
			if [ "$fc" = "!" ]; then
				values="${values:1}";
				echo "$values";
				vType="$values";
			elif $string; then
				echo "string";
				if [ ! -z "$regex" ]; then
					echo;
					echo "var regex$type *regexp.Regexp";
					regexes[$type]="$values";
				fi;
			else
				if $freeChoice; then
					choices=( $(echo "Unknown|$values" | tr "|" " ") );
				else
					choices=( $(echo "$values" | tr "|" " ") );
				fi;
				case ${#choices[@]} in
				1)
					echo "struct{}";;
				*)
					echo "uint8";
					echo;
					echo "const (";
					declare first=true;
					for choice in ${choices[@]};do
						echo -n "	$type$(getName "$choice")";
						if $first; then
							echo -n " $type = iota";
							first=false;
						fi;
						echo;
					done;
					echo ")";
				esac;
				choices=( $(echo "$values" | tr "|" " ") );
			fi;
			echo;

			# decoder

			echo "func (t *$type) decode(vs []parser.Token) error {";
			declare indent="";
			declare vName="vs[0]";
			if $multiple; then
				echo "	for _, v := range vs {";
				indent="	";
				vName="v";
			else
				echo "	if len(vs) != 1 {";
				echo "		return ErrInvalidParam";
				echo "	}";
			fi;
			if $doubleQuote; then
				echo "$indent	if ${vName}.Type != tokenParamQuotedValue {";
				echo "$indent		return ErrInvalidParam";
				echo "$indent	}";
			fi;
			if [ ! -z "$vType" ]; then
				echo "$indent	var q $vType";
				echo "$indent	if err := q.decode(nil, ${vName}.Data); err != nil {";
				echo "$indent		return err";
				echo "$indent	}";
				if $multiple; then
					echo "		*t = append(*t, q)";
				else
					echo "	*t = $type(q)";
				fi;
			elif [ ${#choices[@]} -eq 1 ]; then
				echo "	if strings.ToUpper(${vName}.Data) != \"${choices[0]}\" {";
				echo "		return ErrInvalidParam";
				echo "	}";
			elif [ ${#choices[@]} -gt 1 ]; then
				echo "$indent	switch strings.ToUpper(${vName}.Data) {";
				for choice in ${choices[@]}; do
					echo "$indent	case \"$choice\":";
					if $multiple; then
						echo "		*t = append(*t, $type$(getName "$choice")";
					else
						echo "		*t = $type$(getName "$choice")";
					fi;
				done;
				echo "$indent	default:";
				if $freeChoice; then
					if $multiple; then
						echo "		*t = append(*t, {$type}Unknown)";
					else
						echo "		*t = ${type}Unknown";
					fi;
				else
					echo "$indent		return ErrInvalidParam";
				fi;
				echo "$indent	}";
			else
				if [ -z "$regex" ]; then
					if $multiple; then
						echo "		*t = append(*t, ${vName}.Data)";
					else
						echo "	*t = $type(${vName}.Data)";
					fi;
				else
					echo "$indent	if !regex$type.MatchString(${vName}.Data) {";
					echo "$indent		return ErrInvalidParam";
					echo "$indent	}";
					echo "$indent	*t = ${vName}.Data";
				fi;
			fi;
			if $multiple; then
				echo "	}";
			fi;
			echo "	return nil";
			echo "}";
			echo;

			#encoder

			echo "func (t $type) encode(w writer) {";
			if [ ${#choices} -eq 0 ] || $multiple; then
				if [ "$vType" = "CALADDRESS" -o "$vType" = "URI" ]; then
					echo "	if len(t.String()) == 0 {";
					echo "		return";
					echo "	}";
				elif [ "$vType" = "Boolean" ]; then
					echo "	if !*t {";
					echo "		return";
					echo "	}";
				else
					echo "	if len(*t) == 0 {";
					echo "		return";
					echo "	}";
				fi;
			fi;
			echo "	w.WriteString(\";${keyword}=\")";
			if $multiple; then
				echo "	for n, v := range *t {";
				echo "		if n > 0 {";
				echo "			w.WriteString(\",\")";
				echo "		}";
			else
				vName="*t";
			fi;
			if [ ! -z "$vType" ]; then
				echo "$indent	q := $vType($vName)";
				echo "$indent	q.encode(w)";
			elif [ ${#choices[@]} -eq 1 ]; then
				echo "$indent	w.WriteString(\"${choices[0]}\")";
				freeChoice=true;
			elif [ ${#choices[@]} -gt 1 ]; then
				echo "$indent	switch $vName {";
				for choice in ${choices[@]}; do
					echo "$indent	case $type$(getName "$choice"):";
					echo "$indent		w.WriteString(\"$choice\")";
				done;
				if $freeChoice; then
					echo "$indent	default:";
					echo "$indent		w.WriteString(\"UNKNOWN\")";
				fi;
				echo "$indent	}";
			else
				if $doubleQuote; then
					echo "$indent	w.WriteString(\"\\\"\")";
					echo "$indent	w.WriteString($vName)";
					echo "$indent	w.WriteString(\"\\\"\")";
				else
					echo "$indent	if strings.ContainsAny(string($vName), nonsafeChars[33:]) {";
					echo "$indent		w.WriteString(\"\\\"\")";
					echo "$indent		w.WriteString($vName)";
					echo "$indent		w.WriteString(\"\\\"\")";
					echo "$indent	} else {";
					echo "$indent		w.WriteString(string($vName))";
					echo "$indent	}";
				fi;
			fi;
			if $multiple; then
				echo "	}";
			fi;
			echo "}";
			echo;

			#validator

			echo "func (t $type) valid() bool {";
			if [ "$vType" = "Boolean" ]; then
				echo "	return true";
			elif [ ${#choices[@]} -eq 0 ] || ! $freeChoice; then
				if $multiple; then
					echo "	for _, v := range *t {";
				fi;
				if [ ! -z "$vType" ]; then
					if $multiple; then
					echo "		return !v.validate()";
					else
					echo "	q := $vType(*t)";
					echo "	return q.validate()";
					fi;
				elif [ ${#choices[@]} -gt 0 ]; then
					echo "$indent	switch $vName {";
					echo -n "$indent	case ";
					first=false;
					for choice in ${choices[@]}; do
						if $first; then
							echo -n ", ";
						fi;
						first=true;
						echo -n "$type$(getName "$choice")";
					done;
					echo ":";
					echo "$indent	default:";
					echo "$indent		return false";
					echo "$indent	}";
				elif [ ! -z "$regex" ]; then
					echo "$indent	if !regex${type}.Match($vName) {";
					echo "$indent		return false";
					echo "$indent	}";
				else
					echo "$indent	if strings.ContainsAny($vName, nonsafeChars[:33]) {";
					echo "$indent		return false";
					echo "$indent	}";
				fi;
				if $multiple; then
					echo "	}";
				fi;
			fi;
			if [ -z "$vType" ] ; then
				echo "	return true";
			fi;
			echo "}";
			echo;
		done;
	} < params.gen
	echo "func init() {";
	for key in ${!regexes[@]}; do
		echo "	regex$key = regexp.MustCompile(\"${regexes[$key]}\")";
	done;
	echo "}";
	echo;
	echo "// Errors";
	echo "var (";
	echo "	ErrInvalidParam = errors.New(\"invalid param value\")";
	echo ")";
) > params.go
