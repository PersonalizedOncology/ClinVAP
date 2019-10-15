#!/bin/bash
while [ ! -f /data/completeness.flag ]; do 
sleep 30
done


OPTIND=1
while getopts "t:p:a:" opt; do
    case $opt in
        t) inputFolder=$OPTARG
        ;;
        p) savedOut=$OPTARG
        ;;
        a) assembly=$OPTARG
        ;;
    esac
done
shift "$((OPTIND-1))"

CPWD=$(pwd)
CONTDIR="/opt/vep"
RESULTS="${inputFolder}/results"
LOGS="${inputFolder}/results/logs"
TMP="${inputFolder}/results/tmp"

mkdir -p $LOGS
mkdir $TMP

for file in ${inputFolder}/*.vcf;
do
outfilename=$(basename "$file")
outname="${outfilename%.*}"

# annotate file
echo "################ Starting variant effect prediction ################"
vep -i $file -o $TMP/$outname.vcf --assembly $assembly --config $CONTDIR/.vep/vep.ini 

# check if there are any metadata for patient info
metadata="${outname}"_metadata.json

# create report as json
echo "################ Start to create json ################"
if [ -f docker.flag ]; then # called by docker
    if [ ! -f $inputFolder/$metadata ]; then
        Rscript --no-save --no-restore --no-init-file --no-site-file $CONTDIR/reporting.R -f $TMP/$outname.vcf -r $TMP/$outname.json -g $assembly -c $CONTDIR/GRCh38_01-Jan-2019-ClinicalEvidenceSummaries.txt
    else
       Rscript --no-save --no-restore --no-init-file --no-site-file $CONTDIR/reporting.R -f $TMP/$outname.vcf -r $TMP/$outname.json -m $inputFolder/$metadata -g $assembly -c $CONTDIR/GRCh38_01-Jan-2019-ClinicalEvidenceSummaries.txt
    fi
else
    if [ ! -f $inputFolder/$metadata ]; then
        Rscript --no-save --no-restore --no-init-file --no-site-file $CONTDIR/reporting.R -f $TMP/$outname.vcf -r $TMP/$outname.json -d $CONTDIR/driver_db_dump.json -g $assembly -c $CONTDIR/GRCh38_01-Jan-2019-ClinicalEvidenceSummaries.txt
    else
        Rscript --no-save --no-restore --no-init-file --no-site-file $CONTDIR/reporting.R -f $TMP/$outname.vcf -r $TMP/$outname.json -d $CONTDIR/driver_db_dump.json -m $inputFolder/$metadata -g $assembly -c $CONTDIR/GRCh38_01-Jan-2019-ClinicalEvidenceSummaries.txt
    fi
fi

if [[ $savedOut == *"j"* ]]; then
    cp $TMP/$outname.json $RESULTS
    if [ -f $RESULTS/$outname.json ]; then
        echo "JSON is saved to the volume"
    fi
fi

mv $TMP/*.log $LOGS

echo "################ Start to create report ################"
nodejs $CONTDIR/clinicalreporting_docxtemplater/main.js -d $TMP/$outname.json -t $CONTDIR/clinicalreporting_docxtemplater/data/template.docx -o $TMP/$outname.docx
if [[ $savedOut == *"w"* ]]; then
    cp $TMP/$outname.docx  $RESULTS
    if [ -f $RESULTS/$outname.docx ]; then
        echo "DOCX is saved to the volume"
    fi
fi

    # convert it to pdf
if [[ $savedOut == *"p"* ]]; then
    libreoffice --headless --convert-to pdf $TMP/$outname.docx  --outdir  $RESULTS
    if [ -f $RESULTS/$outname.pdf ]; then
        echo "PDF is saved to the volume"
    fi
fi
# clean tmp directory
find $TMP -type f -amin +30 -delete
done
rm -rf $TMP