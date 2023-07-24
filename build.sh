#!/bin/bash

shopt -s extdebug
shopt -s inherit_errexit
set -e

. build-scripts/loader-extended.bash

loader_addpath build-scripts/

# shellcheck source=build-scripts/libmain.sh
include libmain.sh
# shellcheck source=build-scripts/libbuild.sh
include libbuild.sh
# shellcheck source=build-scripts/libdefer.sh
include libdefer.sh
# shellcheck source=build-scripts/liblog.sh
include liblog.sh
# shellcheck source=build-scripts/libopt.sh
include libopt.sh

function main() {
  local -A options
  libopt_parse options \
    stage:all preset:fast clobber:allow_if_matching_values build_no:0 \
    generate_jenkins_init:no expose_ports:no -- "$@"

  local preset="${options["preset"]}"
  local stage="${options["stage"]}"
  local clobber="${options["clobber"]}"
  local build_no="${options["build_no"]}"
  local generate_jenkins_init="${options["generate_jenkins_init"]}"
  local expose_ports="${options["expose_ports"]}"

  libmain_init iossifovlab.gpf_impala_storage gpf_impala_storage
  libmain_init_build_env \
    clobber:"$clobber" preset:"$preset" build_no:"$build_no" \
    generate_jenkins_init:"$generate_jenkins_init" \
    expose_ports:"$expose_ports" \
    iossifovlab.gpf

  libmain_save_build_env_on_exit
  libbuild_init stage:"$stage" registry.seqpipe.org

  build_run_ctx_init "local"
  defer_ret build_run_ctx_reset

  build_stage "Cleanup"
  {

    build_run_ctx_init "container" "ubuntu:22.04"
    defer_ret build_run_ctx_reset

    build_run rm -rvf ./build-env/*.yaml
    build_run rm -rf /wd/results /wd/sources /wd/channel

    build_run_local mkdir -p results

  }

  build_stage "Clone projects"
  {
    build_run_local mkdir -p projects

    # the quotes around 'EOF' are signifcant - it forces bash to treat the string as literal string until EOF
    build_run_local bash -e -x <<'EOF'
        project_name="iossifovlab.gpf"
        if ! [ -d "projects/$project_name.repo" ]; then
          git clone "ssh://git@github.com/${project_name/.//}" "projects/$project_name.repo"
        fi
EOF

    # the quotes around 'EOF' are signifcant - it forces bash to treat the string as literal string until EOF
    build_run_local env gpf_git_describe="$(e gpf_git_describe)" gpf_git_branch="$(e gpf_git_branch)" bash -e -x << 'EOF'

        project_name="iossifovlab.gpf"
        project_repo_dirname="iossifovlab.gpf.repo"

        cd "projects/$project_repo_dirname"
        git checkout $gpf_git_branch
        git pull --ff-only

        git checkout "$gpf_git_describe"
        cd -
EOF

  }

  local gpf_impala_storage_image="gpf-impala-storage-dev"
  local gpf_impala_storage_image_ref
  # create gpf docker image
  build_stage "Create gpf_impala_storage docker image"
  {
    local gpf_dev_tag
    gpf_dev_tag="$(e docker_img_gpf_dev_tag)"
    build_docker_image_create "$gpf_impala_storage_image" \
        "projects/iossifovlab.gpf.repo/impala_storage" \
        "projects/iossifovlab.gpf.repo/impala_storage/Dockerfile" \
        "$gpf_dev_tag"
    gpf_impala_storage_image_ref="$(e docker_img_gpf_impala_storage_dev)"
  }

  build_stage "Create network"
  {
    # create network
    local -A ctx_network
    build_run_ctx_init ctx:ctx_network "persistent" "network"
    build_run_ctx_persist ctx:ctx_network
  }

  # run impala
  build_stage "Run impala"
  {
    local -A ctx_impala
    build_run_ctx_init ctx:ctx_impala "persistent" "container" "seqpipe/seqpipe-docker-impala:latest" \
        "cmd-from-image" "no-def-mounts" \
        ports:21050,8020 --hostname impala --network "${ctx_network["network_id"]}"

    defer_ret build_run_ctx_reset ctx:ctx_impala

    build_run_container ctx:ctx_impala /wait-for-it.sh -h localhost -p 21050 -t 300

    build_run_ctx_persist ctx:ctx_impala
  }

  # Tests - dae
  build_stage "Tests - impala_storage"
  {

    build_run_ctx_init "container" "${gpf_impala_storage_image_ref}" \
      --network "${ctx_network["network_id"]}" \
      --env DAE_DB_DIR="/wd/data/data-hg19-local/" \
      --env GRR_DEFINITION_FILE="/wd/cache/grr_definition.yaml" \
      --env TEST_REMOTE_HOST="gpfremote" \
      --env DAE_HDFS_HOST="impala" \
      --env DAE_IMPALA_HOST="impala"

    defer_ret build_run_ctx_reset

    for d in /wd/dae /wd/wdae /wd/dae_conftests /wd/impala_storage; do
      build_run_container bash -c 'cd "'"${d}"'"; /opt/conda/bin/conda run --no-capture-output -n gpf \
        pip install -e .'
    done

    build_run_container bash -c '
        cd /wd/impala_storage;
        export PYTHONHASHSEED=0;
        /opt/conda/bin/conda run --no-capture-output -n gpf py.test -v \
          --durations 20 \
          --cov-config /wd/coveragerc \
          --junitxml=/wd/results/dae-junit.xml \
          --cov impala_storage \
          impala_storage/ || true'

    build_run_local cp ./results/dae-junit.xml ./test-results/
  }

}

main "$@"
