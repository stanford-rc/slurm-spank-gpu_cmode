-- ============================================================================
-- SPANK plugin to allow users to choose the compute mode on the GPUs allocated
-- to their job. Requires `nvidia-smi` on the compute node, and the Slurm SPANK
-- Lua plugin.
--
-- Adds a --gpu_cmode=MODE option to srun/sbatch/salloc, with MODE:
--      0: shared
--      1: exclusive (exclusive_thread: deprecated, use 3)
--      2: prohibited
--      3: exclusive (exclusive_process)
--
-- Reference:
-- http://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#compute-modes
--
-- # Author   : Kilian Cavalotti <kilian@stanford.edu>
-- # Created  : 2018/01/22
-- # License  : GPL 2.0
-- ============================================================================


--
-- constants ------------------------------------------------------------------
--

-- plugin name (for logging)
--
myname = "SPANK:gpu_cmode"

-- GPU compute modes definitions
--
valid_cmodes = {
    [0]="shared",
 -- [1]="exclusive thread" deprecated
    [2]="prohibited",
    [3]="exclusive"
}
-- reverse index
--
cmodes_index = {}
for k,v in pairs(valid_cmodes) do cmodes_index[v]=k end

-- default mode
-- GPUs will be reset to that mode at the end of the job
--
default_cmode = "exclusive"


-- define new --gpu_cmode option for srun/salloc/sbatch
--
spank_options = {
    {
        name    = "gpu_cmode",
        usage   = "Set the GPU compute mode on the allocated GPUs to " ..
                  "shared, exclusive or prohibited. Default is " ..
                  default_cmode ,
        arginfo = "<shared|exclusive|prohibited>",
        has_arg = 1,
        cb =      "opt_handler"
    },
}


--
-- functions ------------------------------------------------------------------
--

-- execute command and return output
--
function exec(cmd)
    local handle = io.popen (cmd)
    local result = handle:read("*a") or ""
    handle:close()
    result = string.gsub(result, "\n$", "")
    return result
end

-- validate compute mode
--
function validate_cmode(cmode)
    for _, value in pairs(valid_cmodes) do
        if value == cmode then
            return true
        end
    end
    return false
end

-- check options
--
function opt_handler(val, optarg, isremote)
    cmode = optarg
    if isremote or validate_cmode(optarg) then
        return SPANK.SUCCESS
    end
    return SPANK.FAILURE
end


--
-- SPANK functions ------------------------------------------------------------
-- cf. https://slurm.schedmd.com/spank.html
--

-- SPANK function, called after privileges are temporarily dropped.
-- needs to run as root, but in the job cgroup context, if any.
--
function slurm_spank_task_init_privileged(spank)

    -- if context is not "remote" or compute mode is not defined, do nothing
    if spank.context ~= "remote" or cmode == nil then
        return SPANK.SUCCESS
    end

    -- get GPU ids from CUDA_VISIBLE_DEVICES
    device_ids = spank:getenv("CUDA_VISIBLE_DEVICES")
    if device_ids == nil or device_ids == "" then
        SPANK.log_error(myname .. ": CUDA_VISIBLE_DEVICES not set.")
        return SPANK.FAILURE
    end

    -- check for nvidia-smi
    nvs_path = exec("which nvidia-smi")
    if nvs_path:match("nvidia%-smi$") == nil then
        SPANK.log_error(myname .. ": can't find nvidia-smi in PATH.")
        return SPANK.FAILURE
    end

    -- set compute mode on GPUs
    SPANK.log_info(myname .. ": changing compute mode to '%s' on GPU(s): %s\n",
                   cmode, device_ids)
    local cmd = nvs_path .. " -c " .. cmodes_index[cmode] ..
                            " -i " .. device_ids
    local ret = 0
    if _VERSION <= 'Lua 5.1' then
        ret = tonumber(os.execute(cmd))
    else
        _, _, ret = os.execute(cmd)
    end
    SPANK.log_debug(myname .. ": DEBUG: cmd = %s\n", cmd)
    SPANK.log_debug(myname .. ": DEBUG: ret = %s\n", ret)

    -- check return code
    if ret ~= 0 then
        SPANK.log_error(myname .. ": error setting compute mode go to '%s'" ..
                        " on GPU(s): %s\n", cmode, device_ids)
        return SPANK.FAILURE
    end

    return SPANK.SUCCESS
end


-- SPANK function called for each task as its exit status is collected by Slurm
-- needs to run as root, in the job cgroup context, if any.
--
function slurm_spank_task_exit(spank)

    -- if context is not "remote" or compute mode is not defined, do nothin'
    if spank.context ~= "remote" or cmode == nil then
        return SPANK.SUCCESS
    end

    -- get GPU ids from CUDA_VISIBLE_DEVICES
    device_ids = spank:getenv("CUDA_VISIBLE_DEVICES")
    if device_ids == nil or device_ids == "" then
        SPANK.log_error(myname .. ": CUDA_VISIBLE_DEVICES not set.")
        return SPANK.FAILURE
    end

    -- check for nvidia-smi
    nvs_path = exec("which nvidia-smi")
    if nvs_path:match("nvidia%-smi$") == nil then
        SPANK.log_error(myname .. ": can't find nvidia-smi in PATH.")
        return SPANK.FAILURE
    end

    -- reset compute mode on GPUs
    SPANK.log_info(myname .. ": resetting compute mode to default '%s'" ..
                   " on GPU(s): %s\n", default_cmode, device_ids)
    local cmd = nvs_path .. " -c " .. cmodes_index[default_cmode] ..
                            " -i " .. device_ids
    local ret = 0
    if _VERSION <= 'Lua 5.1' then
        ret = tonumber(os.execute(cmd))
    else
        _, _, ret = os.execute(cmd)
    end
    SPANK.log_debug(myname .. ": DEBUG: cmd = %s\n", cmd)
    SPANK.log_debug(myname .. ": DEBUG: ret = %s\n", ret)

    -- check return
    if ret ~= 0 then
        SPANK.log_error(myname .. ": error resetting compute mode to default"..
                        " '%s' on GPU(s): %s\n", default_cmode, device_ids)
        return SPANK.FAILURE
    end

    return SPANK.SUCCESS
end
