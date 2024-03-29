pipeline=$1

#handle yaml file
parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

eval $(parse_yaml snakemake_config.yaml "config_")

# set timestamp
log_time=`date +"%Y%m%d_%H%M"`
s_time=`date +"%Y%m%d_%H%M%S"`

#clean config_output_dir
output_dir=${config_output_dir%/}

#if pipeline to run on cluster or locally
if [[ $pipeline = "cluster" ]] || [[ $pipeline = "local" ]]; then

  #create log dir
  if [ -d "${output_dir}/log" ]
  then
    echo
    echo "Pipeline re-run, jobid:"
  else
    mkdir "${output_dir}/log"
    echo
    echo "Pipeline initial run, jobid:"
  fi

  # copy config inputs for ref
  files_save=('snakemake_config.yaml' 'cluster_config.yml' ${config_sample_list})

  for f in ${files_save[@]}; do
    IFS='/' read -r -a strarr <<< "$f"
    cp $f "${output_dir}/log/${log_time}_${strarr[-1]}"
  done

  #if cluster - submit job
  if [[ $pipeline = "cluster" ]]; then
    #submit job to cluster
    sbatch --job-name="arriba" --gres=lscratch:200 --time=120:00:00 --mail-type=BEGIN,END,FAIL --output=/home/sevillas2/sbatch/%j_%x.out \
    snakemake --latency-wait 120  -s Snakefile --configfile ${output_dir}/log/${log_time}_snakemake_config.yaml \
    --printshellcmds --cluster-config ${output_dir}/log/${log_time}_cluster_config.yml --keep-going \
    --restart-times 1 --cluster "sbatch --gres {cluster.gres} --cpus-per-task {cluster.threads} \
    -p {cluster.partition} -t {cluster.time} --mem {cluster.mem} --cores {cluster.cores} \
    --job-name={params.rname} --output=${output_dir}/log/${s_time}_{params.rname}.out" -j 500 --rerun-incomplete

  #otherwise submit job locally
  else
    snakemake -s Snakefile --configfile ${output_dir}/log/${log_time}_snakemake_config.yaml \
    --printshellcmds --cluster-config ${output_dir}/log/${log_time}_cluster_config.yml --cores 8
  fi
elif [[ $pipeline = "unlock" ]]; then
  snakemake -s Snakefile --unlock --cores 8
else
  #run snakemake
  snakemake -s Snakefile --configfile snakemake_config.yaml \
  --printshellcmds --cluster-config cluster_config.yml -npr
fi
