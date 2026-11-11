function check_environment(cfg)
%CHECK_ENVIRONMENT Check the actual CPU workflow without reading DAS data.
if nargin<1, cfg = workflow_config(); end
assert(isunix,'The current launcher supports Linux/macOS shell commands.');
assert(~verLessThan('matlab','9.14'),'Use MATLAB R2023a or newer.');
assert(license('test','Signal_Toolbox') && exist('findpeaks','file')~=0, ...
    'Signal Processing Toolbox is required.');
assert(license('test','Distrib_Computing_Toolbox') && exist('parpool','file')~=0, ...
    'Parallel Computing Toolbox is required.');
assert(isfile(cfg.dasqt_python), ...
    'Python not found: %s. Run scripts/setup.sh or set DAS_WORKFLOW_PYTHON.', ...
    cfg.dasqt_python);
addpath(cfg.algorithm_dir,'-begin');
for name = {'mCCFJ','EDWav','GW_mute','GW_mute1'}
    expected = fullfile(cfg.algorithm_dir,[name{1} '.m']);
    assert(strcmp(which(name{1}),expected), ...
        'Unexpected implementation on MATLAB path: %s',name{1});
end
script = fullfile(cfg.project_root,'scripts','check_python.py');
[status,message] = system([shell_quote(cfg.dasqt_python) ' ' shell_quote(script)]);
fprintf('%s',message);
assert(status==0,'Python environment or frozen source verification failed.');
fprintf('MATLAB %s: Signal Processing and Parallel Computing toolboxes available.\n',version);
end
