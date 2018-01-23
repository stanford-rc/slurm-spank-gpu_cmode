# Slurm SPANK GPU Compute Mode plugin

The GPU Compute mode [SPANK](https://slurm.schedmd.com/spank.html) plugin for
[Slurm](https://slurm.schedmd.com/) allows users to choose the compute mode of
GPUs they submit jobs to.

## Rationale

NVIDIA GPUs can be set to operate under different compute modes:

* `Default` (shared): Multiple host threads can use the device
  at the same time.
* `Exclusive-process`: Only one CUDA context may be created on
  the device across all processes in the system.
* `Prohibited`: No CUDA context can be created on the device.

_More information is available in the [CUDA Programming
guide](http://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#compute-modes)_


To ensure optimal performance, process isolation and avoid situations where
multiple processes unintentionally run on the same GPU, it's often recommended
to set the GPU compute mode to `Exclusive-process`.

Unfortunately, some legacy applications may require to run concurrent processes
on a single GPU, to function properly,  and thus need the GPUs to be set in the
`Default` (_i.e._ shared) compute mode.

Hence the need for a mechanism that would allow users to choose the compute
mode of the GPUs their job will run on.


## Installation

**Requirements**:
* [`slurm-spank-lua`](https://github.com/stanford-rc/slurm-spank-lua)
  (submission and execution nodes)
* [`nvidia-smi`](https://developer.nvidia.com/nvidia-system-management-interface)
(execution nodes)

The Slurm SPANK GPU Compute Mode plugin is written in [Lua](http://www.lua.org)
and require the
[`slurm-spank-lua`](https://github.com/stanford-rc/slurm-spank-lua) plugin to
work.


Once the `slurm-spank-lua` plugin is installed and configured, the
`gpu_cmode.lua` script can be dropped in the appropriate directory (by default,
`/etc/slurm/lua.d`, or any other location specified in the `plugstack.conf`
configuration file).


Note that both the Slurm SPANK Lua plugin and the GPU Compute mode Lua plugin
will need to be present on both the submission host(s) (where
`srun`/`sbatch` commands are executed) and the execution host(s) (where the job
actually runs).


_Note_: The plugin defines a default GPU compute mode (`exclusive`), which is
used to re-set the GPUs at the end of a job. The default mode can be changed
by editing the value of `default_cmode` in the script.



## Usage

The Slurm SPANK GPU Compute Mode plugin introduces a new option to `srun` and
`sbatch`: `--gpu_cmode`.

```
$ srun --help
[...]
      --gpu_cmode=<shared|exclusive|prohibited>
                  Set the GPU compute mode on the allocated GPUs to
                  shared, exclusive or prohibited. Default is
                  exclusive
[...]
```

### Examples

##### Requesting `Default` compute mode
  > `--gpu_cmode=shared`

  ```
  $ srun --gres gpu:1 --gpu_cmode=shared "nvidia-smi --query-gpu=compute_mode --format=csv,noheader"
  Default
  ```

##### Requesting `Exclusive-process` compute mode
  > `--gpu_cmode=exclusive`

  ```
  $ srun --gres gpu:1 --gpu_cmode=exclusive "nvidia-smi --query-gpu=compute_mode --format=csv,noheader"
  Exclusive_Process
  ```

##### Requesting `prohibited` compute mode
  > `--gpu_cmode=prohibited`

  ```
  $ srun --gres gpu:1 --gpu_cmode=prohibited "nvidia-smi --query-gpu=compute_mode --format=csv,noheader"
  Prohibited
  ```

##### Multi-GPU job

  ```
  $ srun --gres gpu:4 --gpu_cmode=shared "nvidia-smi --query-gpu=compute_mode --format=csv,noheader"
  Default
  Default
  Default
  Default
  ```

##### Multi-node job

  ```
  $ srun -l -N 2 --ntasks-per-node=1 --gres gpu:1 --gpu_cmode=shared "nvidia-smi --query-gpu=compute_mode --format=csv,noheader"
  1: Default
  0: Default
  ```

**NB**: If the `--gpu_cmode` option is not used, no modification will be made
to the current compute mode of the GPUs, and the site default will be used.

