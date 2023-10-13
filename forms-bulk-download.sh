#!/bin/bash

# Read credentials from "credentials.txt" file
credentials_file="credentials.txt"
if [[ ! -f "$credentials_file" ]]; then
  echo "Error: Credentials file not found."
  exit 1
fi

# Ensure there is a newline at the end of the file
echo >> "$credentials_file"

API_KEY=""
API_SECRET=""
DROPBOX_ACCESS_TOKEN=""
CSV_FOLDER="./CSV"
FORMS_FOLDER="./PDFs"
#ZIPS_FOLDER="./ZIPs"

#create the folders in case they don't exist
mkdir $CSV_FOLDER
mkdir $FORMS_FOLDER
#mkdir $ZIPS_FOLDER

# Read API Key, API Secret, and Dropbox Access Token from the credentials file
while IFS='=' read -r key value; do
  if [[ "$key" == "API_KEY" ]]; then
    API_KEY="${value}"
    echo "API_KEY: $API_KEY"
  elif [[ "$key" == "API_SECRET" ]]; then
    API_SECRET="${value}"
    echo "API_SECRET: $API_SECRET"
  fi
done < "$credentials_file"

if [[ -z "$API_KEY" || -z "$API_SECRET" ]]; then
  echo "Error: Invalid credentials in the credentials file."
  exit 1
fi

#echo "$API_KEY"

#Get token using API credentials
forms_token=$(curl -s -X GET https://api.helloworks.com/v3/token/$API_KEY \
  -H "Authorization: Bearer $API_SECRET") 

JWT=$(echo "$forms_token" | jq -r '.data.token')

#echo "\n Your forms JWT is: $JWT \n"

# Make API request to retrieve all workflows
response=$(curl -s -X GET https://api.helloworks.com/v3/workflows \
  -H "Authorization: Bearer $JWT")

#temporary eceho for dev purposes - comment out later
#echo "List Workflows Response: \n $response \n"

# Extract GUIDs from the API response and store them in an array
# Store all the GUIDs in an array using a temporary file
temp_file=$(mktemp)
temp_file_names=$(mktemp)

echo "$response" | jq -r '.data[].guid' > "$temp_file"
echo "$response" | jq -r '.data[].name' > "$temp_file_names"

# Read the GUIDs & workflow names from the temporary files into an arrays
guids=()
workflow_names=()

#guids into array
while IFS= read -r guid; do
  guids+=("$guid")
done < "$temp_file"

#workflow names into array
while IFS= read -r name; do
  workflow_names+=("$name")
done < "$temp_file_names"


# Remove the temporary file
rm "$temp_file"
rm "$temp_file_names"

#echo GUIDS list for debugging purposes - comment out later
for i in ${!guids[@]}
  do
  echo "guids: ${guids[i]}, ${workflow_names[i]}"
  done


# Declare empty parellel arrays to store values from the first and second columns
#one for IDs and one for the name of the first signer for that instance
instance_ids=()
form_n_signer_names=()

# Loop through each GUID and download the workflow CSV
for i in "${!guids[@]}"; do
  file_name="${workflow_names[i]}.zip"
  
  echo "Downloading CSV for Workflow GUID: ${guids[i]}"
  curl -s -o "$file_name" -X POST https://api.helloworks.com/v3/workflows/${guids[i]}/csv \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/x-www-form-urlencoded" 
  #  --data-urlencode "start_date=2023-01-01T09:35:00Z" \
  #  --data-urlencode "end_date=2023-06-01T09:35:00Z"
  
   echo "ZIP for CSV downloaded for Workflow GUID: ${workflow_names[i]} - ${guids[i]} "
  # Unzip the file
  unzip -o "$file_name" -d "$CSV_FOLDER"
 # Delete the ZIP file
  rm "$file_name"
  echo "Deleted CSV ZIP File: $file_name"
  echo "#############################################"

done

#Store every file name in CSV folder in an array
#TODO
csv_files=()
# Store the list of file names in CSV_FOLDER in a temporary file
temp_file=$(mktemp)
find "$CSV_FOLDER" -type f > "$temp_file"

# Store the file names from the temporary file into an array
csv_files=()
while IFS= read -r file; do
  csv_files+=("$file")
  #echo "CSV file name: $file"
done < "$temp_file"

# Remove the temporary file
rm "$temp_file"
  
# Read the first and second column values and store them in separate arrays
# Store the ids in the first column of each CSV file in an array
instance_ids=()
# Store the names in the second column of each CSV file in an array
form_n_signer_names=()

for file in "${csv_files[@]}"; do
 
  # Read the values in the first and second columns
  values1=()
  values2=()
  #flag variable to ignore first row of csv
  first_row=true
  #variable to capture form name if it's not an empty string.
  form_name="${file:6}"
  while IFS=, read -r value1 value2 _; do
  
  # skip the first row of the CSV 
  if $first_row; then
      first_row=false
      continue
    fi
    values1+=("$value1")
    values2+=("$form_name - $value2")
    #echo "Values: $value1 + $value2"
  done < "$file"

# Add the values to the respective arrays
  instance_ids+=("${values1[@]}")
  form_n_signer_names+=("${values2[@]}")
done

#This block is for debugging purposes - it prints the values in the parallel arrays captures from the CSV
# for i in "${!instance_ids[@]}"; do
#   echo "C1: ${instance_ids[i]} \nC2 ${form_n_signer_names[i]} \n"
#   done

# Loop through each value and download the workflow instance documents
  for i in "${!instance_ids[@]}"; do
    file_name="${form_n_signer_names[i]} - ${instance_ids[i]}"

  #check if folder exists - if yes, skip download for that form since it's already been downloaded
  if [ -d "$FORMS_FOLDER/$file_name" ]; then
    echo "The folder already exists for $file_name. Skipping download."
  else
    echo "Downloading documents for Workflow Instance ID: ${instance_ids[i]} that was sent to ${form_n_signer_names[i]}"
    #Download API Call 
    curl -s -o "$file_name.zip" -X GET https://api.helloworks.com/v3/workflow_instances/${instance_ids[i]}/documents \
    -H "Authorization: Bearer $JWT"
    
    #print download confirmation
    echo "Documents downloaded for Workflow Instance ID: ${instance_ids[i]} that was sent to ${form_n_signer_names[i]}"
  
    #Create Folder to unzip Forms from this workflow into
    mkdir "$FORMS_FOLDER/$file_name"
    echo "Unzipping $file_name"
    unzip -o -q "$file_name" -d "$FORMS_FOLDER/$file_name"
    # Delete the ZIP file
    #mv "$file_name.zip" "$ZIPS_FOLDER"
    echo "Deleted ZIP File: $file_name"
    rm "$file_name.zip"
    echo "############################################################"
  fi
done
echo "############################################################\nEND"

#################################################################################
#     #DROPBOX API PART - code below is mostly outdated & wrong
#################################################################################
#     # Upload the downloaded document to Dropbox
#     # echo "Uploading document to Dropbox for Workflow Instance ID: $col1"
#     # curl -X POST \
#     #   --header "Authorization: Bearer $DROPBOX_ACCESS_TOKEN" \
#     #   --header "Dropbox-API-Arg: {\"path\": \"$FORMS_FOLDER/${col2}_instance_$col1.zip\",\"mode\": \"add\",\"autorename\": true,\"mute\": false}" \
#     #   --header "Content-Type: application/octet-stream" \
#     #   --data-binary "@${col2}_instance_$col1.zip" \
#     #   https://content.dropboxapi.com/2/files/upload
#     # echo "Document uploaded to Dropbox for Workflow Instance ID: $col1"

#     # # Remove the downloaded document file
#     # rm "${col2}_instance_$col1.zip"

#   done

#   echo "CSV processed for Workflow GUID: $guid"
# done

# # Print the arrays of column values
# echo "Values in the first column:"
# for value in "${instance_ids[@]}"; do
#   echo "$value"
# done

# echo "Values in the second column:"
# for value in "${form_n_signer_names[@]}"; do
#   echo "$value"
# done
