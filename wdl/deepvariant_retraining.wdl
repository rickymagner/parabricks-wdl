version 1.0

struct RuntimeAttributes {
    Int diskGB
    Int nThreads
    Int gbRAM
    String hpcQueue
    Int runtimeMinutes
    String gpuDriverVersion
    Int maxPreemptAttempts
}

struct GPUAttributes {
    String gpuModel
    Int nGPU
}

task make_examples {

    input {
        File ref
        File bam
        File bam_index
        File truth_vcf 
        File truth_vcf_index
        File truth_bed 
        String examples_name
        String region

        RuntimeAttributes runtimeAttributes = {
            "diskGB": 500,
            "nThreads": 24,
            "gbRAM": 120,
            "hpcQueue": "gpu",
            "runtimeMinutes": 600,
            "gpuDriverVersion": "460.73.01",
            "maxPreemptAttempts": 3
        }

        GPUAttributes gpuAttributes = {
            "gpuModel": "nvidia-tesla-t4",
            "nGPU": 4,
        }
    }

    String docker_image = "nvcr.io/nvidia/clara/deepvariant_train:4.1.0-1"
    String binary_path = "/usr/local/parabricks/binaries/bin/deepvariant"
    String outbase = basename(bam, ".bam")
    String examples_basename = basename(examples_name, ".gz")

    command {
        ~{binary_path} \
        ~{ref} \
        ~{bam} \
        2 \
        -o ~{outbase}.vcf \
        -n 8 \
        --channel_insert_size \
        -L "~{region}" \
        -disable-use-window-selector-model \
        --mode training \
        --truth_variants ~{truth_vcf} \
        --confident_regions ~{truth_bed} \
        --examples ~{examples_name} \
        -z 4
    }

    output {
        Array[File] made_examples = glob("~{examples_basename}*")
    }

    runtime {
        docker: "~{docker_image}"
        disks : "local-disk ~{runtimeAttributes.diskGB} SSD"
        cpu : runtimeAttributes.nThreads
        memory : "~{runtimeAttributes.gbRAM} GB"
        hpcMemory : runtimeAttributes.gbRAM
        hpcQueue : "~{runtimeAttributes.hpcQueue}"
        hpcRuntimeMinutes : runtimeAttributes.runtimeMinutes
        gpuType : "~{gpuAttributes.gpuModel}"
        gpuCount : gpuAttributes.nGPU
        nvidiaDriverVersion : "~{runtimeAttributes.gpuDriverVersion}"
        zones : ["us-central1-a", "us-central1-b", "us-central1-c"]
        preemptible : runtimeAttributes.maxPreemptAttempts
    }
}

task shuffle_data {

    input {
        Array[File] examples # The output of make_examples from the previous step
        String output_dataset_name = "HG001"
        String mode  # Must be either "training" or "validation"

        RuntimeAttributes runtimeAttributes = {
            "diskGB": 500,
            "nThreads": 24,
            "gbRAM": 120,
            "hpcQueue": "gpu",
            "runtimeMinutes": 600,
            "gpuDriverVersion": "460.73.01",
            "maxPreemptAttempts": 3
        }

        GPUAttributes gpuAttributes = {
            "gpuModel": "nvidia-tesla-t4",
            "nGPU": 4,
        }
    }

    String shuffle_data_script_link = "https://api.ngc.nvidia.com/v2/resources/nvidia/clara/parabricks_deepvariant_retraining_notebook/versions/4.0.0-1/files/parabricks_deepvariant_retraining_notebook.zip"
    String input_pattern_list = mode + "_set_gpu.with_label.tfrecord-?????-of-00004.gz"
    String output_pattern_prefix = mode + "_set_gpu.with_label.shuffled"
    String output_dataset_config = mode + "_set_gpu.pbtxt"

    command {
        apt install -y wget && \
        wget --content-disposition ~{shuffle_data_script_link} && \
        unzip parabricks_deepvariant_retraining_notebook.zip &&
        python3 scripts/shuffle_tfrecords_lowmem.py \
            --input_pattern_list=~{input_pattern_list} \
            --output_pattern_prefix=~{output_pattern_prefix} \
            --output_dataset_config=~{output_dataset_config} \
            --output_dataset_name=~{output_dataset_name} \
            --direct_num_workers=8 \
            --step=-1
    }

    output {
        Array[File] shuffled_examples = glob("~{output_pattern_prefix}*")
    }

    runtime {
        docker: "nvcr.io/nvidia/tensorflow:23.03-tf2-py3"
        disks : "local-disk ~{runtimeAttributes.diskGB} SSD"
        cpu : runtimeAttributes.nThreads
        memory : "~{runtimeAttributes.gbRAM} GB"
        hpcMemory : runtimeAttributes.gbRAM
        hpcQueue : "~{runtimeAttributes.hpcQueue}"
        hpcRuntimeMinutes : runtimeAttributes.runtimeMinutes
        gpuType : "~{gpuAttributes.gpuModel}"
        gpuCount : gpuAttributes.nGPU
        nvidiaDriverVersion : "~{runtimeAttributes.gpuDriverVersion}"
        zones : ["us-central1-a", "us-central1-b", "us-central1-c"]
        preemptible : runtimeAttributes.maxPreemptAttempts
    }
}

task training {

    input {
        Array[File] train_examples
        Array[File] val_examples
        String training_output_dataset_config
        String validation_output_dataset_config
        Int number_of_steps = 5000
        Int batch_size = 32 
        Float learning_rate = 0.0005
        Int save_interval_secs = 300

        RuntimeAttributes runtimeAttributes = {
            "diskGB": 500,
            "nThreads": 24,
            "gbRAM": 120,
            "hpcQueue": "gpu",
            "runtimeMinutes": 600,
            "gpuDriverVersion": "460.73.01",
            "maxPreemptAttempts": 3
        }

        GPUAttributes gpuAttributes = {
            "gpuModel": "nvidia-tesla-t4",
            "nGPU": 4,
        }
    }

    String bin_version = "1.4.0"
    String training_dir = "training"

    String model_bucket="gs://deepvariant/models/DeepVariant/~{bin_version}/DeepVariant-inception_v3-~{bin_version}+data-wgs_standard"
    String gcs_pretrained_wgs_model="~{model_bucket}/model.ckpt"

    String docker_image = "google/deepvariant:~{bin_version}-gpu"

    command {
        /opt/deepvariant/bin/model_eval \
            --dataset_config_pbtxt=~{training_output_dataset_config} \
            --checkpoint_dir=~{training_dir} \
            --batch_size=512 &

        /opt/deepvariant/bin/model_train \
            --dataset_config_pbtxt=~{validation_output_dataset_config} \
            --train_dir=~{training_dir} \
            --model_name="inception_v3" \
            --number_of_steps=~{number_of_steps} \
            --save_interval_secs=~{save_interval_secs} \
            --batch_size=~{batch_size} \
            --learning_rate=~{learning_rate} \
            --start_from_checkpoint="~{gcs_pretrained_wgs_model}"
    }

    output {
        Array[File] training_dir = glob("~{training_dir}/*")
    }

    runtime {
        docker: "tensorflow/tensorflow"
        disks : "local-disk ~{runtimeAttributes.diskGB} SSD"
        cpu : runtimeAttributes.nThreads
        memory : "~{runtimeAttributes.gbRAM} GB"
        hpcMemory : runtimeAttributes.gbRAM
        hpcQueue : "~{runtimeAttributes.hpcQueue}"
        hpcRuntimeMinutes : runtimeAttributes.runtimeMinutes
        gpuType : "~{gpuAttributes.gpuModel}"
        gpuCount : gpuAttributes.nGPU
        nvidiaDriverVersion : "~{runtimeAttributes.gpuDriverVersion}"
        zones : ["us-central1-a", "us-central1-b", "us-central1-c"]
        preemptible : runtimeAttributes.maxPreemptAttempts
    }
}

workflow DeepVariant_Retraining {

    input {
        # Make Examples 
        File ref
        File bam
        File bam_index
        File truth_vcf 
        File truth_vcf_index
        File truth_bed 

        String training_region
        String validation_region

        String training_examples_name = "training_set_gpu.with_label.tfrecord.gz"
        String validation_examples_name = "validation_set_gpu.with_label.tfrecord.gz"

        # Training 
        Int number_of_steps = 5000
        Int batch_size = 32 
        Float learning_rate = 0.0005
        Int save_interval_secs = 300 
    }

    ## Make training examples 
    call make_examples as make_examples_train {
        input:
            ref=ref,
            bam=bam,
            bam_index=bam_index,
            truth_vcf=truth_vcf,
            truth_vcf_index=truth_vcf_index,
            truth_bed=truth_bed,
            examples_name=training_examples_name,
            region=training_region
    }

    ## Make validation examples 
    call make_examples as make_examples_val {
        input:
            ref=ref,
            bam=bam,
            bam_index=bam_index,
            truth_vcf=truth_vcf,
            truth_vcf_index=truth_vcf_index,
            truth_bed=truth_bed,
            examples_name=validation_examples_name,
            region=validation_region
    }

    ## Shuffle training data 
    call shuffle_data as shuffle_data_train {
        input: 
            examples=make_examples_train.made_examples,
            mode="training"
    }

    ## Shuffle validation data 
    call shuffle_data as shuffle_data_val {
        input: 
            examples=make_examples_val.made_examples,
            mode="validation"
    }

    ## Run DeepVariant Retraining 
    call training {
        input: 
            train_examples=shuffle_data_train.shuffled_examples,
            val_examples=shuffle_data_val.shuffled_examples,
            training_output_dataset_config="training_set_gpu.pbtxt",
            validation_output_dataset_config="validation_set_gpu.pbtxt",
            number_of_steps=number_of_steps,
            batch_size =batch_size,
            learning_rate=learning_rate,
            save_interval_secs=save_interval_secs
    }

    output {
        Array[File] training_dir=training.training_dir
    }

    meta {
        Author: "NVIDIA Parabricks"
    }
}
