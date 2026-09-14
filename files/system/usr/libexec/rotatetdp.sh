#!/usr/bin/bash

current_mode=$(hhdctl get tdp.lenovo.tdp.mode | cut -d '=' -f 2)

if [ "$1" = "rotate" ]; then
	case $current_mode in
	quiet)
		next_mode=balanced
		;;
	balanced)
		next_mode=performance
		;;
	performance)
		next_mode=custom
		;;
	custom)
		next_mode=quiet
		;;
	*)
		echo "Unknown mode: $current_mode"
		exit 1
		;;
	esac
	hhdctl set tdp.lenovo.tdp.mode="$next_mode" &>/dev/null
	current_mode=$next_mode
fi

case $current_mode in
quiet)
	echo '{"percentage": 1}'
	;;
balanced)
	echo '{"percentage": 30}'
	;;
performance)
	echo '{"percentage": 60}'
	;;
custom)
	echo '{"percentage": 80}'
	;;
*)
	echo '{"percentage": 0}'
	exit 1
	;;
esac
