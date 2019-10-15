## Introduction
The Clinical Variant Annotation Pipeline (ClinVAP) extracts information from simple somatic mutations (SNVs) of a patient given in VCF files and creates structured clinical reports by annotating, prioritizing and filtering the genomic variants. The report is designed to provide assistance for Molecular Tumor Boards (MTB) in making therapeutic decisions by equipping them with the molecular mechanisms initiating carcinogenesis and actionable genes. 

**Disclaimer**
The report created by ClinVAP is intended as a hypothesis generating framework and thus for research use only, and not for diagnostic or clinical purposes. Information provided in the report does not replace a physician's medical judgment and usage is entirely at your own risk. The providers of this resource shall in no event be liable for any direct, indirect, incidental, consequential, or exemplary damages.

## Pipeline Components
The pipeline consists of two major components which are the database instance, and the reporting application. The database is queried by the reporting application to annotate the genes as drivers and to reveal the cancer drugs targeting the mutated genes. The reporting application uses Ensembl Variant Effect Prediction (VEP) to predict the variant effects, R based processing script to process, filter and prioritise the variants, and docxtemplater mail merging tool to render the results into the report template. 

### Database
The genes are annotated with their action type i.e. Tumor suppressor gene (TSG), or Oncogene if they are identified as driver. They are further annotated with the information of their targeting drugs. Those information is incorporated into a MongoDB database and queried by the reporting application for every somatic variant from the patient.

Information on the driver genes are collected from public databases and literature such as COSMIC v81, TSGene2.0, UniProtKB, Rubio-Perez et al. and Vogelstein et al.  

Information on drugs is collected from DrugBank 5.0.7, Therapeutic Target Database (TTD), The International Union of Basic and Clinical Pharmacology 2017.5. 

### Reporting Application

**Ensembl VEP.**  The first step of the pipeline is to annotate the variants given in VCF file using Ensembl VEP v93. Please note that the VCF output should include somatic variants only. Depending on NGS pipeline that originally produced the VCF file, there should be somatic status information in its information field descriptions. If you have a mixed VCF file containing somatic and germline variants, please filter your input file according to the somatic status annotation. The annotation is conducted according to the human genome assembly version (GRCh37 or GRCh38) specified by user. SIFT and Polyphen are employed in the VEP for further annotation to reveal the effect of variants provided in the input file over the function of the proteins. SIFT is used to identify whether an amino acid substitution leads to a non-synonymous single nucleotide polymorphism (nsSNP), and hence to categorise the mutations as "deleterious" (damaging) or "tolerated". The PolyPhen software tool is used to label the variants as "probably damaging", "possibly damaging" or "benign". 
![Clinical Reporting Pipeline Workflow](https://github.com/PersonalizedOncology/ClinicalReportingPipeline/blob/master/doc/PipelineWorkflow.jpeg)

**R Based Reporting Application.** The output of the variant effect prediction is channeled into R based reporting application to further process the data and extract the necessary information to create the report. The variant effects predicted as "low" or "moderate" are filtered along with the predictions of SIFT and PolyPhen as "tolerated" or "low confidence tolerated" and "benign".  For the remaining variants, the database is queried to identify driver genes and approved cancer drugs targeting the affected genes. Approved cancer drugs targeting the affected genes are also identified using the database. As an indication of the significance of the results, we calculated confidence score for both driver genes and the drug-gene pairs. The confidence score for driver genes shows the number of the background resources that listed the queried gene as a driver. The confidence score for the drug-gene pairs represents the number of references that contains the information on the association. Clinical evidence summaries from the CIViC database are also incorporated to find therapeutics that have evidence of targeting the genes and the observed variants. The results are outputted as *JSON* file. 
Patient metadata in *JSON* format is also parsed here, and merged with the output file. Please note that, for the application to identify the metadata, it has to have the same name as the input *VCF* file with *\_metadata.JSON* extension and be structured as follows:

{  
"patient\_firstname":"\<NAME>",  
"patient\_lastname":"\<SURNAME>",  
"patient\_dateofbirth":"\<DATE>",  
"patient\_diagnosis_short":"\<DIAGNOSIS>",  
"mutation\_load":"\<LOAD>"  
}  
If the diagnosis is provided within the metadata file, the pipeline returns gene-drug associations that is specific to the cancer type. Please use the disease dictionary file to find the correct disease ontology for the ClinVAP pipeline (<https://github.com/PersonalizedOncology/ClinVAP/blob/master/doc/disease_names_dictionary.txt>)

**Rendering report via docxtemplater tool.** The JSON output of the R script is rendered into a word template.

## Implementation
### Running the pipeline with Docker
**System requirements**  
 1. Docker Engine release 1.13.0+  
 2. Compose release 1.10.0+  
 3. 34 GB of physical empty space on Docker Disk Image  
 4. Availability of the ports 5000 and 27021, i.e. not being used by other application.

**Availability** 
 
All images are publicly available on Docker Hub at [ https://hub.docker.com/u/personalizedoncology]( https://hub.docker.com/u/personalizedoncology). The application orchestrates four images via docker-compose which are:  

* Data deployment image, *clinvap\_file\_deploy*: Transfer the files that are necessary to run Ensembl VEP offline
* Database images, *clinvap\_reporting\_db* and *clinvap\_reporting\_db\_api*: Starts the MongoDB database and Rest API service to conduct driver gene and mechanistic drug target annotation
* Reporting image, *clinvap\_reporting\_app*: Processes the input VCF file and outputs the report. Depends on the Data deployment image and the database image. 

**Implementation For Mac and Ubuntu Users** 

```1. git clone https://github.com/PersonalizedOncology/ClinVAP.git```         
```2. cd ClinVAP/```          
```3. export ASSEMBLY=<Your Assembly Here>```              
```4. docker-compose run -e ASSEMBLY --service-ports ClinicalReportR -t /inout -p jwp -a <Your Assembly Here>```        

* `-a`: The genome assembly that was used in variant calling calling step to generate your VCF files.
	* `GRCh37` or
	* `GRCh38`
* `-t`: Directory hosting input files. It is handled by docker-compose file. Do not change this parameter. 
* `-p`: Output format to save the results. Select the corresponding argument here to get the report in specific format(s).
	* `j` to save report in JSON format  
	* `w` to save report in DOCX format  
	* `p` to save report in PDF format  


Resulting files should be in the host volume, *./ReportingApplication/inout* under the *ClinVAP* directory. Please note that volumes are handled by docker compose file.

**Implementation With Docker Toolbox For Windows Users**. 
Implementation only differs by the third command. Rest of the specifications are same. 

```1. git clone https://github.com/PersonalizedOncology/ClinVAP.git```          
```2. cd ClinVAP/```            
```3. export ASSEMBLY=<Your Assembly Here>```                   
```4. docker-compose run -e ASSEMBLY --service-ports ClinicalReportR -t //inout -p jwp -a <Your Assembly Here>```        



### Running the pipeline with Singularity

On high performance computing clusters, the usage of Docker containers is usually not permitted due to security considerations. For this reason, ClinVAP is also offered as Singularity images. 

**System requirements**   
1. Singularity 2.4+  
2. 12 GB of free space on home directory  
3. Availability of the ports 5000 and 27021, i.e. not being used by other application.

**Availability**
All the images are publicly available on Singularity Hub, [https://singularity-hub.org/collections/2168](https://singularity-hub.org/collections/2168)

**Implementation**
	
1. Pull reporting image from Singularity Hub.  
`singularity pull -n reporting_app.img  shub://PersonalizedOncology/ClinVAP:report`
2. Pull dependency files image from Singularity Hub.   
`singularity pull -n file_deploy.img  shub://PersonalizedOncology/ClinVAP:filedeploy`
3. Run dependency files image first to transfer those file on your local folder. 
singularity run -B /LOCAL/PATH/TO/FILES:/mnt file_deploy.img -a <Your Assembly Here>`
4. Run the reporting image to generate the clinical reports. 
`singularity run -B /LOCAL/PATH/TO/FILES:/data -B /PATH/TO/INPUT/DATA:/inout reporting_app.img -t /inout -p jwp -a <Your Assembly Here>`

### Software Availability

The source code for this software is open source and available on [https://github.com/PersonalizedOncology/ClinVAP](https://github.com/PersonalizedOncology/ClinVAP)

If you would like to contribute, you may   
1. open an issue on GitHub,
2. fork the repository, make changes and submit a pull request for us to review the changes and merge your contribution. 

Please contact us on sueruen@informatik.uni-tuebingen.de for further information/help. 