#!/bin/bash

################################################################################################################
### LAMEDB 2 TVHEADEND CHANNEL CONVERTER #######################################################################
################################################################################################################

# Info page with lamedb syntax explanation
# https://raw.github.com/OpenViX/enigma2/master/lib/dvb/frontendparms.h

e2settingsdir=$1
outputdir=$2
piconurl=$3
picondir=$4

################################################################################################################
### CHECKS #####################################################################################################
################################################################################################################

if [ ! -d "$outputdir" ] || [ ! -f "$e2settingsdir/lamedb" ] || ! sed -n "1{p;q}" "$e2settingsdir/lamedb" | grep -q '4'; then
    echo "ERROR: Check your directories, lamedb should be version 4."
    echo "USAGE: /lamedb2tvheadend.sh /e2settingsdir /outputdir http://localhost /picondir"
    echo ""
    echo "Press [ENTER] to exit..."
    read input
    exit 1
fi

################################################################################################################
### BASIC SETUP ################################################################################################
################################################################################################################

if [ -d "/dev/shm" ]; then
    tempdir=/dev/shm/lamedb2tvh_temp
else
    tempdir=$(dirname $0)/lamedb2tvh_temp
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
    
    SERVICETYPE=${channelref[4]}
    ORBITALREF=$(echo "$hexSAT" | sed 's/0*//')
    
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

            NETWORKTYPE="dvb_network_dvbs"
            
            case ${tuninginfo[3]} in
                0) POLARIZATION="H";;           #0=Horizontal
                1) POLARIZATION="V";;           #1=Vertical
                2) POLARIZATION="L";;           #2=CircularLeft
                3) POLARIZATION="R";;           #3=CircularRight
            esac

            case ${tuninginfo[4]} in
                0) FEC="AUTO";;                 #0=Auto
                1) FEC="1/2";;                  #1=1/2
                2) FEC="2/3";;                  #2=2/3
                3) FEC="3/4";;                  #3=3/4
                4) FEC="5/6";;                  #4=5/6
                5) FEC="7/8";;                  #5=7/8
                6) FEC="8/9";;                  #6=8/9
                7) FEC="3/5";;                  #7=3/5
                8) FEC="4/5";;                  #8=4/5
                9) FEC="9/10";;                 #9=9/10
               10) FEC="6/7";;                  #10=6/7
               15) FEC="NONE";;                 #15=None
            esac

            case ${tuninginfo[8]} in
             ""|0) SYSTEM="DVBS";;              #0=DVB-S
                1) SYSTEM="DVBS2";;             #1=DVB-S2
            esac

            case ${tuninginfo[9]} in
                0) MODULATION="AUTO";;          #0=Auto
             ""|1) MODULATION="QPSK";;          #1=QPSK
                2) MODULATION="8PSK";;          #2=8PSK
                3) MODULATION="QAM16";;         #3=QAM16
            esac

            case ${tuninginfo[10]} in
                0) ROLLOFF="35";;               #0=0.35
                1) ROLLOFF="25";;               #1=0.25
                2) ROLLOFF="20";;               #2=0.20
             ""|3) ROLLOFF="AUTO";;             #3=Auto
            esac

            case ${tuninginfo[11]} in
                0) PILOT="OFF";;                #0=Off
                1) PILOT="ON";;                 #1=On
             ""|2) PILOT="AUTO";;               #2=Unknown
            esac

            case ${tuninginfo[5]} in
             "-"*) SATPOS="DVB-S "$(echo "${tuninginfo[5]}" | sed 's/-//' | awk '{print $0/10}')"W";;
                *) SATPOS="DVB-S "$(echo "${tuninginfo[5]}" | awk '{print $0/10}')"E";;
            esac
            FREQUENCY="${tuninginfo[1]}"
            SYMBOLRATE="${tuninginfo[2]}"
        ;;
        t)
            # DVB-T/T2
            # 0     1           2           3           4           5           6               7       8           9           10      11
            # TYPE  FREQUENCY   BANDWIDTH   CODERATE HP CODERATE LP MODULATION  TRANSMISSION    GUARD   HIERARCHY   INVERSION   FLAGS   SYSTEM
            # t     498000000   0           5           5           3           2               4       4           2           0
            # t     722000000   0           5           5           3           2               4       4           2           0       1

            NETWORKTYPE="dvb_network_dvbt"
            POLARIZATION="NONE"
            
            case ${tuninginfo[2]} in
                0) BANDWIDTH="8Mhz";;           #0=8Mhz
                1) BANDWIDTH="7Mhz";;           #1=7Mhz
                2) BANDWIDTH="6Mhz";;           #2=6Mhz
                3) BANDWIDTH="AUTO";;           #3=Auto
                4) BANDWIDTH="5Mhz";;           #4=5Mhz
                5) BANDWIDTH="1712kHz";;        #5=1_712MHz
                6) BANDWIDTH="10Mhz";;          #6=10Mhz
            esac

            case ${tuninginfo[3]} in
                0) CODERATEHP="1/2";;           #0=1/2
                1) CODERATEHP="2/3";;           #1=2/3
                2) CODERATEHP="3/4";;           #2=3/4
                3) CODERATEHP="5/6";;           #3=5/6
                4) CODERATEHP="7/8";;           #4=7/8
                5) CODERATEHP="AUTO";;          #5=Auto
                6) CODERATEHP="6/7";;           #6=6/7
                7) CODERATEHP="8/9";;           #7=8/9
            esac

            case ${tuninginfo[4]} in
                0) CODERATELP="1/2";;           #0=1/2
                1) CODERATELP="2/3";;           #1=2/3
                2) CODERATELP="3/4";;           #2=3/4
                3) CODERATELP="5/6";;           #3=5/6
                4) CODERATELP="7/8";;           #4=7/8
                5) CODERATELP="AUTO";;          #5=Auto
                6) CODERATELP="6/7";;           #6=6/7
                7) CODERATELP="8/9";;           #7=8/9
            esac

            case ${tuninginfo[5]} in
                0) MODULATION="QPSK";;          #0=QPSK
                1) MODULATION="QAM16";;         #1=QAM16
                2) MODULATION="QAM64";;         #2=QAM64
                3) MODULATION="AUTO";;          #3=Auto
                4) MODULATION="QAM256";;        #4=QAM256
            esac

            case ${tuninginfo[6]} in
                0) TRANSMISSION="2k";;          #0=2k
                1) TRANSMISSION="8k";;          #1=8k
                2) TRANSMISSION="AUTO";;        #2=Auto
                3) TRANSMISSION="4k";;          #3=4k
                4) TRANSMISSION="1k";;          #4=1k
                5) TRANSMISSION="16k";;         #5=16k
                6) TRANSMISSION="32k";;         #6=32k
            esac

            case ${tuninginfo[7]} in
                0) GUARD="1/32";;               #0=32
                1) GUARD="1/16";;               #1=16
                2) GUARD="1/8";;                #2=8
                3) GUARD="1/4";;                #3=4
                4) GUARD="AUTO";;               #4=Auto
                5) GUARD="1/128";;              #5=128
                6) GUARD="19/128";;             #6=19_128
                7) GUARD="19/256";;             #7=19_256
            esac

            case ${tuninginfo[8]} in
                0) HIERARCHY="NONE";;           #0=None
                1) HIERARCHY="1";;              #1=1
                2) HIERARCHY="2";;              #2=2
                3) HIERARCHY="4";;              #3=4
                4) HIERARCHY="AUTO";;           #4=Auto
            esac

            case ${tuninginfo[10]} in
             ""|0) SYSTEM="DVBT";;              #0=DVB-T
                1) SYSTEM="DVBT2";;             #1=DVB-T2
            esac

            SATPOS="DVB-T"
            FREQUENCY="${tuninginfo[1]}"
            SYMBOLRATE="27500000"
        ;;
        c)
            # DVB-C
            # 0     1           2           3           4           5   6
            # TYPE  FREQUENCY   SYMBOLRATE  INVERSION   MODULATION  FEC FLAGS
            # c     364000      6875000     2           3           15  0
            # c     372000      6875000     2           5           0   0
            # c     412000      6875000     2           5           0   d

            NETWORKTYPE="dvb_network_dvbc"
            POLARIZATION="NONE"
            
            case ${tuninginfo[4]} in
                0) MODULATION="AUTO";;          # 0=Auto
                1) MODULATION="QAM16";;         # 1=QAM16
                2) MODULATION="QAM32";;         # 2=QAM32
                3) MODULATION="QAM64";;         # 3=QAM64
                4) MODULATION="QAM128";;        # 4=QAM128
                5) MODULATION="QAM256";;        # 5=QAM256
            esac

            case ${tuninginfo[5]} in
                0) FEC="AUTO";;                 # 0=Auto
                1) FEC="1/2";;                  # 1=1/2
                2) FEC="2/3";;                  # 2=2/3
                3) FEC="3/4";;                  # 3=3/4
                4) FEC="5/6";;                  # 4=5/6
                5) FEC="7/8";;                  # 5=7/8
                6) FEC="8/9";;                  # 6=8/9
               10) FEC="6/7";;                  # 10=6/7
               15) FEC="NONE";;                 # 15=None
            esac    

            SYSTEM="DVBC_ANNEX_AC"
            SATPOS="DVB-C"
            FREQUENCY="${tuninginfo[1]}"
            SYMBOLRATE="${tuninginfo[2]}"
        ;;
    esac

    SID=$(printf "%d\n" "0x$hexSID")
    NID=$(printf "%d\n" "0x$hexNID")
    TID=$(printf "%d\n" "0x$hexTID")
    
    NETWORKDIR=$tempdir/tvh_channellist/input/dvb/networks/$(echo "$SATPOS" | md5sum | cut -f1 -d" ")
    MUXDIR=$NETWORKDIR/muxes/$(echo "$SATPOS$FREQUENCY$POLARIZATION" | md5sum | cut -f1 -d" ")
    SERVICESDIR=$MUXDIR/services

    if ! [ -d $SERVICESDIR ]; then
        mkdir -p $SERVICESDIR
    fi
    
    echo -e "{" > $NETWORKDIR/config
    echo -e "\t\"networkname\": \"$SATPOS\"," >> $NETWORKDIR/config
    echo -e "\t\"nid\": 0," >> $NETWORKDIR/config
    echo -e "\t\"autodiscovery\": true," >> $NETWORKDIR/config
    echo -e "\t\"skipinitscan\": false," >> $NETWORKDIR/config
    echo -e "\t\"class\": \"$NETWORKTYPE\"" >> $NETWORKDIR/config
    echo -e "}" >> $NETWORKDIR/config
    
    echo -e "{" > $MUXDIR/config
    echo -e "\t\"delsys\": \"$SYSTEM\"," >> $MUXDIR/config
    echo -e "\t\"frequency\": $FREQUENCY," >> $MUXDIR/config

    case ${tuninginfo[0]} in
        s)
            echo -e "\t\"symbolrate\": $SYMBOLRATE," >> $MUXDIR/config
            echo -e "\t\"polarisation\": \"$POLARIZATION\"," >> $MUXDIR/config
            echo -e "\t\"modulation\": \"$MODULATION\"," >> $MUXDIR/config
            echo -e "\t\"fec\": \"$FEC\"," >> $MUXDIR/config
            echo -e "\t\"rolloff\": \"$ROLLOFF\"," >> $MUXDIR/config
            echo -e "\t\"pilot\": \"$PILOT\"," >> $MUXDIR/config
        ;;
        t)
            echo -e "\t\"bandwidth\": $BANDWIDTH," >> $MUXDIR/config
            echo -e "\t\"constellation\": \"$MODULATION\"," >> $MUXDIR/config
            echo -e "\t\"transmission_mode\": \"$TRANSMISSION\"," >> $MUXDIR/config
            echo -e "\t\"guard_interval\": \"$GUARD\"," >> $MUXDIR/config
            echo -e "\t\"hierarchy\": \"$HIERARCHY\"," >> $MUXDIR/config
            echo -e "\t\"fec_hi\": \"$CODERATEHP\"," >> $MUXDIR/config
            echo -e "\t\"fec_lo\": \"$CODERATELP\"," >> $MUXDIR/config
        ;;
        c)
            echo -e "\t\"symbolrate\": $SYMBOLRATE," >> $MUXDIR/config
            echo -e "\t\"constellation\": \"$MODULATION\"," >> $MUXDIR/config
            echo -e "\t\"fec\": \"$FEC\"," >> $MUXDIR/config
        ;;
    esac

    echo -e "\t\"enabled\": true," >> $MUXDIR/config
    echo -e "\t\"onid\": $NID," >> $MUXDIR/config
    echo -e "\t\"tsid\": $TID," >> $MUXDIR/config
    echo -e "\t\"initscan\": false" >> $MUXDIR/config
    echo -e "}" >> $MUXDIR/config
    
    SERVICE=$SERVICESDIR/$(echo "$ORBITALREF$SID$NID$TID" | md5sum | cut -f1 -d" ")
    echo -e "{" > $SERVICE
    echo -e "\t\"sid\": $SID," >> $SERVICE
    echo -e "\t\"lcn\": 0," >> $SERVICE
    echo -e "\t\"svcname\": \"$CHANNELNAME\"," >> $SERVICE
    echo -e "\t\"provider\": \"$PROVIDERNAME\"," >> $SERVICE
    echo -e "\t\"dvb_servicetype\": $SERVICETYPE," >> $SERVICE
    echo -e "\t\"enabled\": true," >> $SERVICE
    echo -e "\t\"pcr\": 0," >> $SERVICE
    echo -e "\t\"stream\": [" >> $SERVICE
    echo -e "\t]" >> $SERVICE
    echo -e "}" >> $SERVICE

done

echo ""

################################################################################################################
### CONVERT GROUPS #############################################################################################
################################################################################################################

mkdir -p $tempdir/tvh_channellist/channeltags
echo "All Channels:1" > $tempdir/tags

tagfile=$tempdir/tvh_channellist/channeltags/1
echo -e "{" > $tagfile
echo -e "\t\"enabled\": 1," >> $tagfile
echo -e "\t\"internal\": 0," >> $tagfile
echo -e "\t\"titledIcon\": 0," >> $tagfile
echo -e "\t\"name\": \"All Channels\"," >> $tagfile
echo -e "\t\"comment\": \"\"," >> $tagfile
echo -e "\t\"icon\": \"\"," >> $tagfile
echo -e "\t\"id\": 1" >> $tagfile
echo -e "}" >> $tagfile


currentline=1
grep -h -o -e 'userbouquet.*tv' -e 'userbouquet.*radio' $e2settingsdir/bouquets.tv $e2settingsdir/bouquets.radio | while read filename ; do
    currentline=$((currentline+1))
    bouquet=$(echo "${filename##*.}" | tr [a-z] [A-Z])" - "$(sed -n "1{p;q}" $e2settingsdir/$filename | sed -e 's/#NAME //g' -e 's/:/ /' -e 's/;/ /' -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    echo "$bouquet:$currentline" >> $tempdir/tags
    
    tagfile=$tempdir/tvh_channellist/channeltags/$currentline
    echo -e "{" > $tagfile
    echo -e "\t\"enabled\": 1," >> $tagfile
    echo -e "\t\"internal\": 0," >> $tagfile
    echo -e "\t\"titledIcon\": 0," >> $tagfile
    echo -e "\t\"name\": \"$bouquet\"," >> $tagfile
    echo -e "\t\"comment\": \"\"," >> $tagfile
    echo -e "\t\"icon\": \"\"," >> $tagfile
    echo -e "\t\"id\": $currentline" >> $tagfile
    echo -e "}" >> $tagfile
done

mkdir -p $tempdir/tvh_channellist/channel

linescount=$(grep -h -o -e 'userbouquet.*tv' -e 'userbouquet.*radio' $e2settingsdir/bouquets.tv $e2settingsdir/bouquets.radio | wc -l)
currentline=0
grep -h -o -e 'userbouquet.*tv' -e 'userbouquet.*radio' $e2settingsdir/bouquets.tv $e2settingsdir/bouquets.radio | while read filename ; do
    currentline=$((currentline+1))
    echo -ne "Converting group: $currentline/$linescount"\\r

    bouquet=$(echo "${filename##*.}" | tr [a-z] [A-Z])" - "$(sed -n "1{p;q}" $e2settingsdir/$filename | sed -e 's/#NAME //g' -e 's/:/ /' -e 's/;/ /' -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    TAG=$(grep -h "$bouquet:" $tempdir/tags | sed "s;$bouquet:;;g")

    grep -h -o '1:0:.*:.*:.*:.*:.*:0:0:0:' $e2settingsdir/$filename | tr [A-Z] [a-z] | while read line ; do
        serviceref=(${line//:/ })
        SID=$(printf "%d\n" "0x${serviceref[3]}")
        NID=$(printf "%d\n" "0x${serviceref[5]}")
        TID=$(printf "%d\n" "0x${serviceref[4]}")
        ORBITALREF="${serviceref[6]}"
        serviceID=$(echo "$ORBITALREF$SID$NID$TID" | md5sum | cut -f1 -d" ")
        channel=$tempdir/tvh_channellist/channel/$(echo "$serviceID" | md5sum | cut -f1 -d" ")
        
        picon=$(echo "${serviceref[0]}_${serviceref[1]}_${serviceref[2]}_${serviceref[3]}_${serviceref[4]}_${serviceref[5]}_${serviceref[6]}_${serviceref[7]}_${serviceref[8]}_${serviceref[9]}" | tr [a-z] [A-Z])
        if [ -f "$picondir/$picon.png" ]; then
            picon="$piconurl/$picon.png"
        else
            picon=""
        fi
        
        if [ -f $channel ]; then
            echo -e "\t\t$TAG," >> $channel
        else
            echo -e "{" > $channel
            echo -e "\t\"number\": 0," >> $channel
            echo -e "\t\"icon\": \"$picon\"," >> $channel
            echo -e "\t\"dvr_pre_time\": 0," >> $channel
            echo -e "\t\"dvr_pst_time\": 0," >> $channel
            echo -e "\t\"services\": [" >> $channel
            echo -e "\t\t\"$serviceID\"" >> $channel
            echo -e "\t]," >> $channel
            echo -e "\t\"tags\": [" >> $channel
            echo -e "\t\t$TAG," >> $channel
        fi
    done
done

for file in $tempdir/tvh_channellist/channel/* ; do
    echo -e "\t\t1" >> $file
    echo -e "\t]" >> $file
    echo -e "}" >> $file
done

################################################################################################################
### OUTPUT FILES ###############################################################################################
################################################################################################################

rm -rf $outputdir/tvh_channellist
cp -R $tempdir/tvh_channellist $outputdir/tvh_channellist

################################################################################################################
### CLEANUP ####################################################################################################
################################################################################################################

rm -rf $tempdir

echo ""
echo "Done!"
