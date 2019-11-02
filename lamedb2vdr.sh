#!/bin/bash

################################################################################################################
### LAMEDB 2 VDR CHANNEL CONVERTER #############################################################################
################################################################################################################

# Info page with lamedb syntax explanation
# https://raw.github.com/OpenViX/enigma2/master/lib/dvb/frontendparms.h

e2settingsdir=$1
outputdir=$2

################################################################################################################
### CHECKS #####################################################################################################
################################################################################################################

if [ ! -d "$outputdir" ] || [ ! -f "$e2settingsdir/lamedb" ] || ! sed -n "1{p;q}" "$e2settingsdir/lamedb" | grep -q '4'; then
    echo "ERROR: Check your directories, lamedb should be version 4."
    echo "USAGE: /lamedb2vdr.sh /e2settingsdir /outputdir"
    echo ""
    echo "Press [ENTER] to exit..."
    read input
    exit 1
fi

################################################################################################################
### BASIC SETUP ################################################################################################
################################################################################################################

if [ -d "/dev/shm" ]; then
    tempdir=/dev/shm/lamedb2vdr_temp
else
    tempdir=$(dirname $0)/lamedb2vdr_temp
fi

mkdir $tempdir

cat $e2settingsdir/lamedb | iconv -f UTF-8 -t MS-ANSI -c | iconv -f MS-ANSI -t UTF-8 -c > $tempdir/lamedb
sed -i -e 's/\(^....:........:....:....:.*:.*\)/\L\1/' -e 's/\(^........:....:....\)/\L\1/' $tempdir/lamedb

################################################################################################################
### CONVERT ####################################################################################################
################################################################################################################

linescount=$(grep -h -o '^....:........:....:....:.*:.*' $tempdir/lamedb | wc -l)
currentline=0

grep -h -o '^....:........:....:....:.*:.*' $tempdir/lamedb | while read line ; do

    currentline=$((currentline+1))
    echo -ne "Converting channel: $currentline/$linescount"\\r

    channelref=(${line//:/ })
    hexSID=${channelref[0]}
    hexTID=${channelref[2]}
    hexNID=${channelref[3]}
    hexSAT=${channelref[1]}

    tuningref=$hexSAT":"$hexTID":"$hexNID
    channelref=$hexSID":"$tuningref

    channelinfo=$(grep -A2 $channelref $tempdir/lamedb)

    CHANNELNAME=$(echo "$channelinfo" | sed -n "2p" | sed -e 's/:/ /' -e 's/;/ /' -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    if [ -z "$CHANNELNAME" ]; then
        CHANNELNAME="-"
    fi
    PROVIDERNAME=$(echo "$channelinfo" | sed -n "3p" | grep -o -e 'p:.*' | sed -e "s/,.*//g" -e 's/p://g' -e 's/:/ /' -e 's/;/ /' -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    if [ -z "$PROVIDERNAME" ]; then
        PROVIDERNAME="-"
    fi

    tuninginfo=$(echo $(grep -A2 $tuningref $tempdir/lamedb | sed -n "2p"))
    tuninginfo=(${tuninginfo//:/ })

    case ${tuninginfo[0]} in
        s)
            # DVB-S/S2
            # 0     1           2           3               4   5       6           7       8       9           10      11
            # TYPE  FREQUENCY   SYMBOLRATE  POLARIZATION    FEC SATPOS  INVERSION   FLAGS   SYSTEM  MODULATION  ROLLOFF PILOT
            # s     12284000    27500000    0               4   130     2           0
            # s     12475500    29900000    0               3   130     2           0       1       2           0       2

            case ${tuninginfo[3]} in
                0) POLARIZATION="H";;           #0=Horizontal
                1) POLARIZATION="V";;           #1=Vertical
                2) POLARIZATION="L";;           #2=CircularLeft
                3) POLARIZATION="R";;           #3=CircularRight
            esac

            case ${tuninginfo[4]} in
                0) FEC="C999";;                 #0=Auto
                1) FEC="C12";;                  #1=1/2
                2) FEC="C23";;                  #2=2/3
                3) FEC="C34";;                  #3=3/4
                4) FEC="C56";;                  #4=5/6
                5) FEC="C78";;                  #5=7/8
                6) FEC="C89";;                  #6=8/9
                7) FEC="C35";;                  #7=3/5
                8) FEC="C45";;                  #8=4/5
                9) FEC="C910";;                 #9=9/10
               10) FEC="C67";;                  #10=6/7
               15) FEC="C0";;                   #15=None
            esac

            case ${tuninginfo[6]} in
                0) INVERSION="I0";;             #0=Off
                1) INVERSION="I1";;             #1=On
                2) INVERSION="";;               #2=Unknown
            esac

            case ${tuninginfo[8]} in
             ""|0) SYSTEM="S0";;                #0=DVB-S
                1) SYSTEM="S1";;                #1=DVB-S2
            esac

            case ${tuninginfo[9]} in
                0) MODULATION="M999";;          #0=Auto
             ""|1) MODULATION="M2";;            #1=QPSK
                2) MODULATION="M5";;            #2=8PSK
                3) MODULATION="M16";;           #3=QAM16
            esac

            case ${tuninginfo[10]} in
                0) ROLLOFF="O35";;              #0=0.35
                1) ROLLOFF="O25";;              #1=0.25
                2) ROLLOFF="O20";;              #2=0.20
             ""|3) ROLLOFF="";;                 #3=Auto
            esac

            case ${tuninginfo[11]} in
                0) PILOT="P0";;                 #0=Off
                1) PILOT="P1";;                 #1=On
             ""|2) PILOT="";;                   #2=Unknown
            esac

            # I0 V C23 M5 O25 S1 P0
            PARAMETER=$INVERSION$POLARIZATION$FEC$MODULATION$ROLLOFF$SYSTEM$PILOT

            case ${tuninginfo[5]} in
             "-"*) SATPOS="S"$(echo "${tuninginfo[5]}" | sed 's/-//' | awk '{print $0/10}')"W";;
                *) SATPOS="S"$(echo "${tuninginfo[5]}" | awk '{print $0/10}')"E";;
            esac
            FREQUENCY=$(echo "${tuninginfo[1]}" | awk '{printf "%.0f\n", $1/1000}')
            SYMBOLRATE=$(echo "${tuninginfo[2]}" | awk '{printf "%.0f\n", $1/1000}')
        ;;
        t)
            # DVB-T/T2
            # 0     1           2           3           4           5           6               7       8           9           10      11
            # TYPE  FREQUENCY   BANDWIDTH   CODERATE HP CODERATE LP MODULATION  TRANSMISSION    GUARD   HIERARCHY   INVERSION   FLAGS   SYSTEM
            # t     498000000   0           5           5           3           2               4       4           2           0
            # t     722000000   0           5           5           3           2               4       4           2           0       1

            case ${tuninginfo[2]} in
                0) BANDWIDTH="B8";;             #0=8Mhz
                1) BANDWIDTH="B7";;             #1=7Mhz
                2) BANDWIDTH="B6";;             #2=6Mhz
                3) BANDWIDTH="";;               #3=Auto
                4) BANDWIDTH="B5";;             #4=5Mhz
                5) BANDWIDTH="B1712";;          #5=1_712MHz
                6) BANDWIDTH="B10";;            #6=10Mhz
            esac

            case ${tuninginfo[3]} in
                0) CODERATEHP="C12";;           #0=1/2
                1) CODERATEHP="C23";;           #1=2/3
                2) CODERATEHP="C34";;           #2=3/4
                3) CODERATEHP="C56";;           #3=5/6
                4) CODERATEHP="C78";;           #4=7/8
                5) CODERATEHP="C999";;          #5=Auto
                6) CODERATEHP="C67";;           #6=6/7
                7) CODERATEHP="C89";;           #7=8/9
            esac

            case ${tuninginfo[4]} in
                0) CODERATELP="D12";;           #0=1/2
                1) CODERATELP="D23";;           #1=2/3
                2) CODERATELP="D34";;           #2=3/4
                3) CODERATELP="D56";;           #3=5/6
                4) CODERATELP="D78";;           #4=7/8
                5) CODERATELP="D999";;          #5=Auto
                6) CODERATELP="D67";;           #6=6/7
                7) CODERATELP="D89";;           #7=8/9
            esac

            case ${tuninginfo[5]} in
                0) MODULATION="M2";;            #0=QPSK
                1) MODULATION="M16";;           #1=QAM16
                2) MODULATION="M64";;           #2=QAM64
                3) MODULATION="M999";;          #3=Auto
                4) MODULATION="M256";;          #4=QAM256
            esac

            case ${tuninginfo[6]} in
                0) TRANSMISSION="T2";;          #0=2k
                1) TRANSMISSION="T8";;          #1=8k
                2) TRANSMISSION="";;            #2=Auto
                3) TRANSMISSION="T4";;          #3=4k
                4) TRANSMISSION="T1";;          #4=1k
                5) TRANSMISSION="T16";;         #5=16k
                6) TRANSMISSION="T32";;         #6=32k
            esac

            case ${tuninginfo[7]} in
                0) GUARD="G32";;                #0=32
                1) GUARD="G16";;                #1=16
                2) GUARD="G8";;                 #2=8
                3) GUARD="G4";;                 #3=4
                4) GUARD="";;                   #4=Auto
                5) GUARD="G128";;               #5=128
                6) GUARD="G19128";;             #6=19_128
                7) GUARD="G19256";;             #7=19_256
            esac

            case ${tuninginfo[8]} in
                0) HIERARCHY="Y0";;             #0=None
                1) HIERARCHY="Y1";;             #1=1
                2) HIERARCHY="Y2";;             #2=2
                3) HIERARCHY="Y4";;             #3=4
                4) HIERARCHY="";;               #4=Auto
            esac

            case ${tuninginfo[9]} in
                0) INVERSION="I0";;             #0=Off
                1) INVERSION="I1";;             #1=On
                2) INVERSION="";;               #2=Unknown
            esac

            case ${tuninginfo[10]} in
             ""|0) SYSTEM="S0";;                #0=DVB-T
                1) SYSTEM="S1";;                #1=DVB-T2
            esac

            # I0 B8 C34 D0 M16 T8 G4 Y0 S0
            PARAMETER=$INVERSION$BANDWIDTH$CODERATEHP$CODERATELP$MODULATION$TRANSMISSION$GUARD$HIERARCHY$SYSTEM

            SATPOS="T"
            FREQUENCY=$(echo "${tuninginfo[1]}" | awk '{printf "%.0f\n", $1/1000}')
            SYMBOLRATE="27500"
        ;;
        c)
            # DVB-C
            # 0     1           2           3           4           5   6
            # TYPE  FREQUENCY   SYMBOLRATE  INVERSION   MODULATION  FEC FLAGS
            # c     364000      6875000     2           3           15  0
            # c     372000      6875000     2           5           0   0
            # c     412000      6875000     2           5           0   d

            case ${tuninginfo[3]} in
                0) INVERSION="I0";;             # 0=Off
                1) INVERSION="I1";;             # 1=On
                2) INVERSION="";;               # 2=Unknown
            esac

            case ${tuninginfo[4]} in
                0) MODULATION="M999";;          # 0=Auto
                1) MODULATION="M16";;           # 1=QAM16
                2) MODULATION="M32";;           # 2=QAM32
                3) MODULATION="M64";;           # 3=QAM64
                4) MODULATION="M128";;          # 4=QAM128
                5) MODULATION="M256";;          # 5=QAM256
            esac

            case ${tuninginfo[5]} in
                0) FEC="C999";;                 # 0=Auto
                1) FEC="C12";;                  # 1=1/2
                2) FEC="C23";;                  # 2=2/3
                3) FEC="C34";;                  # 3=3/4
                4) FEC="C56";;                  # 4=5/6
                5) FEC="C78";;                  # 5=7/8
                6) FEC="C89";;                  # 6=8/9
               10) FEC="C67";;                  # 10=6/7
               15) FEC="C0";;                   # 15=None
            esac    

            # I0 C0 M256
            PARAMETER=$INVERSION$FEC$MODULATION

            SATPOS="C"
            FREQUENCY=${tuninginfo[1]}
            SYMBOLRATE=$(echo "${tuninginfo[2]}" | awk '{printf "%.0f\n", $1/1000}')
        ;;
    esac

    SID=$(printf "%d\n" "0x$hexSID")
    NID=$(printf "%d\n" "0x$hexNID")
    TID=$(printf "%d\n" "0x$hexTID")
    VPID="0"
    APID="0"
    TPID="0"
    CAID="0"

    echo "$CHANNELNAME;$PROVIDERNAME:$FREQUENCY:$PARAMETER:$SATPOS:$SYMBOLRATE:$VPID:$APID:$TPID:$CAID:$SID:$NID:$TID:0" >> $tempdir/channels.conf
    echo "$hexSAT:$SATPOS" >> $tempdir/sats_unsorted

done

echo ""

awk '!x[$0]++' $tempdir/sats_unsorted > $tempdir/sats_sorted

################################################################################################################
### CONVERT GROUPS #############################################################################################
################################################################################################################

linescount=$(grep -h -o -e 'userbouquet.*tv' -e 'userbouquet.*radio' $e2settingsdir/bouquets.tv $e2settingsdir/bouquets.radio | wc -l)
currentline=0

grep -h -o -e 'userbouquet.*tv' -e 'userbouquet.*radio' $e2settingsdir/bouquets.tv $e2settingsdir/bouquets.radio | while read filename ; do

    currentline=$((currentline+1))
    echo -ne "Converting group: $currentline/$linescount"\\r

    bouquet=$(echo "${filename##*.}" | tr [a-z] [A-Z])" - "$(sed -n "1{p;q}" $e2settingsdir/$filename | sed -e 's/#NAME //g' -e 's/:/ /' -e 's/;/ /' -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    echo ":$bouquet" >> $tempdir/full_fav_channels.conf
    echo ":$bouquet" >> $tempdir/chorder_template.conf

    grep -h -o '1:0:.*:.*:.*:.*:.*:0:0:0:' $e2settingsdir/$filename | tr [A-Z] [a-z] | while read line ; do
        serviceref=(${line//:/ })
        SID=$(printf "%d\n" "0x${serviceref[3]}")
        NID=$(printf "%d\n" "0x${serviceref[5]}")
        TID=$(printf "%d\n" "0x${serviceref[4]}")

        SAT=$(grep -h ${serviceref[6]} $tempdir/sats_sorted)
        SAT=(${SAT//:/ })
        SAT=${SAT[1]}

        grep -h -o ".*:$SAT:.*:$SID:$NID:$TID:0" $tempdir/channels.conf >> $tempdir/full_fav_channels.conf
        echo ".*:$SAT:.*:$SID:$NID:$TID:0" >> $tempdir/chorder_template.conf
    done

done

echo ":New Channels" >> $tempdir/full_fav_channels.conf
echo ":New Channels" >> $tempdir/chorder_template.conf

################################################################################################################
### OUTPUT FILES ###############################################################################################
################################################################################################################

sed 's/^.*://g' $tempdir/sats_sorted | sort | uniq | while read line ; do
    echo ":$line" >> $tempdir/final_channels.conf
    grep -h -o ".*:$line:.*" $tempdir/channels.conf | sort >> $tempdir/final_channels.conf
done
echo ":New Channels" >> $tempdir/final_channels.conf

awk '!x[$0]++' $tempdir/full_fav_channels.conf > $outputdir/favorites_channels.conf
cp $tempdir/chorder_template.conf $outputdir/chorder_template.conf
cp $tempdir/final_channels.conf $outputdir/channels.conf

################################################################################################################
### CLEANUP ####################################################################################################
################################################################################################################

rm -rf $tempdir

echo ""
echo "Done!"
