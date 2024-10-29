#!/bin/bash

# Define log file
LOG_FILE="provisioning.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to install packages
provisioning_install_packages() {
    log_message "Installing APT packages: ${APT_PACKAGES[*]}"
    sudo apt-get update
    sudo apt-get install -y "${APT_PACKAGES[@]}"
}

# Function to check if jq is installed and install it if not
install_jq() {
    if ! command -v jq &> /dev/null; then
        log_message "jq could not be found, installing..."
        sudo apt-get update
        sudo apt-get install -y jq
        log_message "jq has been installed."
    else
        log_message "jq is already installed."
    fi
}

# Function to download models from the config.json file
download_models_from_config() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        log_message "Config file not found: $config_file"
        return 1
    fi

    # Install jq if it's not installed
    install_jq

    # Read tokens from environment variables
    local hf_token="${HF_TOKEN:-}"
    local civitai_token="${CIVITAI_TOKEN:-}"

    # Check if tokens are set
    if [ -z "$hf_token" ]; then
        log_message "HF_TOKEN environment variable is not set."
    fi
    if [ -z "$civitai_token" ]; then
        log_message "CIVICAI_TOKEN environment variable is not set."
    fi

    # Create folders if they don't exist
    mkdir -p models clip lora vae unet controlnet checkpoints

    # Download models from various sections
    download_model_type "esrgan_models" "${WORKSPACE}/storage/stable_diffusion/models/models" "$config_file" "$hf_token" "$civitai_token"
    download_model_type "unet_models" "${WORKSPACE}/storage/stable_diffusion/models/unet" "$config_file" "$hf_token" "$civitai_token"
    download_model_type "vae_models" "${WORKSPACE}/storage/stable_diffusion/models/vae" "$config_file" "$hf_token" "$civitai_token"
    download_model_type "lora_models" "${WORKSPACE}/storage/stable_diffusion/models/lora" "$config_file" "$hf_token" "$civitai_token"
    download_model_type "clip_models" "${WORKSPACE}/storage/stable_diffusion/models/clip" "$config_file" "$hf_token" "$civitai_token"
    download_model_type "controlnet_models" "${WORKSPACE}/storage/stable_diffusion/models/controlnet" "$config_file" "$hf_token" "$civitai_token"
    download_model_type "checkpoint_models" "${WORKSPACE}/storage/stable_diffusion/models/checkpoints" "$config_file" "$hf_token" "$civitai_token"
}

# Function to download a specific type of model
download_model_type() {
    local model_type="$1"
    local folder="$2"
    local config_file="$3"
    local hf_token="$4"
    local civitai_token="$5"

    # Extract models from the config.json file
    local models=$(jq -r ".${model_type}[] | \"\(.url) \(.filename? // .url)\"" "$config_file")

    # Download models
    log_message "Downloading $model_type..."
    IFS=$'\n' read -d '' -r -a model_urls <<< "$models"
    for model_info in "${model_urls[@]}"; do
        local url=$(echo "$model_info" | awk '{print $1}')
        local filename=$(echo "$model_info" | awk '{print $2}')

        mkdir $folder -p

        # Extract the base name of the file if the filename is a URL$folder
        filename=$(basename "$filename")

        provisioning_download_model "$url" "$folder/$filename" "$hf_token" "$civitai_token"
    done
}

# Function to download a single model
provisioning_download_model() {
    local url="$1"
    local filepath="$2"
    local hf_token="$3"
    local civitai_token="$4"

    # Check if the file already exists
    if [ -f "$filepath" ]; then
        log_message "File $(basename "$filepath") already exists, skipping download."
        return 0
    fi

    local domain=$(echo "$url" | awk -F/ '{print $3}')

    # Set up authentication header if needed
    local auth_header=""
    if [[ "$domain" == *"huggingface.co"* ]]; then
        auth_header="Authorization: Bearer $hf_token"
    elif [[ "$domain" == *"civitai.com"* ]]; then
        auth_header="Authorization: Bearer $civitai_token"
    fi

    # Download the file with --quiet to suppress extra output while still showing the progress
    log_message "Downloading $(basename "$filepath") from $url to $filepath..."
    if [ -n "$auth_header" ]; then
        wget --header="$auth_header" --quiet --show-progress -O "$filepath" "$url"
    else
        wget --quiet --show-progress -O "$filepath" "$url"
    fi

    if [ $? -eq 0 ]; then
        log_message "Downloaded $(basename "$filepath") successfully."
    else
        log_message "Failed to download $(basename "$filepath")."
    fi
}


# Main function to enhance the script
provisioning_enhance() {
    # Read config from environment variables
    local load_config="${LOAD_CONFIG:-}"

    # Check if tokens are set
    if [ -z "$load_config" ]; then
        log_message "Load Config environment variable is not set."
    fi

    wget  --quiet --show-progress -O "config.json" "$load_config"
    local config_file="config.json"

    # Install packages from the APT package list in the config file
    provisioning_install_packages

    # Download models from the config.json file
    download_models_from_config "$config_file"
}

setup_syncthing() {
    # Read config from environment variables
    local syncthing_config="${SYNCTHING_CONFIG:-}"

    # Check if config is set
    if [ -z "$syncthing_config" ]; then
        log_message "Syncthing Config environment variable is not set."
    fi

    # Read tokens from environment variables
    local dev1="${DEV1:-}"
    local dev2="${DEV2:-}"

    wget  --quiet --show-progress -O "config.xml" "$syncthing_config"
    local syncthing_config_file="config.xml"
    
    syncthing_output_file="config_env.xml"
    
    # Replace DEV1 and DEV2 with their environment variable values
    sed -e "s/\$DEV1/$dev1/g" \
        -e "s/\$DEV2/$dev2/g" "$syncthing_config_file" > "$syncthing_output_file"
    
    cp $syncthing_output_file "/workspace/home/user/.local/state/syncthing/config.xml"
}

# Run the enhanced script
provisioning_enhance
#'setup_syncthing
