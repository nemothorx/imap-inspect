#!/bin/bash

# some curl-isms from https://stackoverflow.com/questions/72655471/curl-imap-how-to-get-multiple-email-messages-with-one-command
# and http://server1.sharewiz.net/doku.php?id=curl:perform_imap_queries_using_curl
# and of course https://everything.curl.dev/usingcurl/reademail

                        # runtime hints: 
# generic option template
#       ./imap-inspect.sh [-v|-id|-vm] [folder-filter]
#           '-v' options are not required but must be $1 if it's included
#           'folder-filter' is not required. Simply limits all actions to matching folders. 'grep' simplicity

# obtain a list of folders with message count per folder
#       ./imap-inspect.sh

# obtain summary headerss for the "INBOX/Job Responses" mailbox only
#       ./imap-inspect.sh -v "INBOX/Job" | grep From:

# obtain count-of-messages-per-day sorted sanely:
#       ./imap-inspect.sh -vd

# obtain count-of-messages-per-month sorted sanely, for INBOX.spamassassin only
#       ./imap-inspect.sh -vm INBOX.spamassassin

# hardcode imap server/login/password values here if you like
#imapsvr=
#userlogin=
#passwd=

# let's prompt for anything not hardcoded
[ -z "$imapsvr" ] && read -p "remote server (eg: 'mail.server-thing.com'): " imapsvr
[ -z "$imapsvr" ] && echo "! I need a server" && exit 1

[ -z "$userlogin" ] && read -p "login username: " userlogin
[ -z "$userlogin" ] && echo "! I need a username" && exit 1

[ -z "$passwd" ] && read -s -p "password: " passwd && echo ""
[ -z "$passwd" ] && echo "! I need a passwd" && exit 1

# echo "i:$imapsvr"
# echo "u:$userlogin"
# echo "p:$passwd"
# exit 1


### functions
do_summarise() {
    case $verbose in
        # these both assume Date: header will include the format of DD MMM YYYY, which is only true in about 99.99% of cases. See RFC 5322 (and as mentioned in date(1) for why this assumption is being made
        *day*)
                cat /dev/stdin | grep "^  Date: " | grep -o -E ".. ... 20(0|1|2)." | sed -e "s/^0/ /g" | sort -k 3g,3 -k 2M,2 -k 1g | uniq -c  | sed -e 's/\(\s*[0-9]*\)\s*\(.*\)/\2 : \1/g'
        ;;
        *month*)
            cat /dev/stdin | grep "^  Date: " | grep -o -E "... 20(0|1|2)." | sed -e "s/^0/ /g" | sort -k 2g,2 -k 1M | uniq -c | sed -e 's/\(\s*[0-9]*\)\s*\(.*\)/\2 : \1/g' 
            ;;
        *)
            cat /dev/stdin
    esac

}

verbose="Count-per-folder" # this exact string is tested later! Change it in sync with below
[ "$1" == "-v" ] && verbose="verbose with summary of headers per message" && shift
[ "$1" == "-vd" ] && verbose="verbose with summary of messages per-day" && shift
[ "$1" == "-vm" ] && verbose="verbose with summary of messages per-month" && shift
folderfilter=${1:-.}

curlopts="--no-progress-meter -s"

# if you have a masteruser (eg, dovecot):
#  - please ensure it is restricted to secure IPs
#  - use this auth instead, and provide masteruser and password somewhere
#auth="$userlogin*$masteruser:$masterpassword"
auth="$userlogin:$passwd"

# get all the folders. Handle both . and / delimiters
flist=$(curl $curlopts -u "$auth" "imaps://$imapsvr/" 2>&1 | tr -d '\r' | grep LIST | sed -e 's^* LIST .* "[./]" ^^g' )

echo "# $userlogin [imaps://$imapsvr] ($verbose)"
echo ""
#echo ">$flist<"
#exit
echo "$flist" | grep "${folderfilter}" | grep -v '{'| while read folder ; do

    # summary of the INBOX
    f1=$(echo "$folder" | sed -e 's/\\\*/\\\\\\\*/g')           # for "examine" with filesystem literal "\*", both need escaping and so becomes a literal "\\\*"
#    echo ">$folder< >$f1<"
    # TODO: this awk should be smarter - test for a number as $2 and EXISTS in $3. Thus avoiding folders with "EXISTS" in the name
#    echo "curl $curlopts -u \"$auth\" \"imaps://$imapsvr/\" -X \"EXAMINE ${f1}\""
    exists=$(curl $curlopts -u "$auth" "imaps://$imapsvr/" -X "EXAMINE ${f1}" | awk '/EXISTS/ {print $2}')

    echo "## ${folder} ($exists messages)"
    # get key headers for these messages. This time the folder needs to be named differently

    if [ "$verbose" != "Count-per-folder" ] ; then      # basing our verbosity off this exact string! Change them in sync with above
        f2=$(echo "{$folder}" | tr -d '"' | sed -e 's/ /%20/g ; s/\\\*/%2A/g')
#       echo ">$f2<"
#        curl $curlopts -u "$auth" "imap://127.0.0.1/${f2};mailindex=[1-${exists}];section=header.fields%20(date%20from%20to%20subject%20received)"  | sed -e 's/^/  /g' | do_summarise
        curl $curlopts -u "$auth" "imaps://$imapsvr/${f2};mailindex=[1-${exists}];section=header.fields%20(date%20from%20to%20subject)"  | sed -e 's/^/  /g' | do_summarise
#    echo "curl $curlopts -u \"$auth\" \"imap://127.0.0.1/\" -X \"EXAMINE ${f1}\" | grep EXISTS | cut -d\" \" -f 2"
        echo ""
    fi

done

folderfails=$(echo "$flist" | grep -c "{")
if [ "$folderfails" -gt 0 ] ; then
    echo ""
    echo "Note: $folderfails folders not checked due to unhandle-able names"
fi

