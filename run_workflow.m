function cfg = run_workflow(config_file,stage)
%RUN_WORKFLOW Run the portable DASQt -> EDWav -> PSD CCF -> F-J workflow.
%   run_workflow('configs/local.json')
%   run_workflow('configs/local.json','pick')       % interactive MATLAB
%   run_workflow('configs/local.json','attenuation')% reuse saved polygon
if nargin<1, config_file = ''; end
if nargin<2, stage = ''; end
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'matlab'),'-begin');
cfg = workflow_config(config_file,stage);
check_environment(cfg);
if strcmp(cfg.stage,'pick') && ~usejava('desktop')
    error('Workflow:DesktopRequired', ...
        'stage=pick requires interactive MATLAB. Run preview in batch first.');
end
if strcmp(cfg.stage,'attenuation')
    assert(isfile(fullfile(cfg.out_dir,'manual_mask_polygon.mat')), ...
        'No saved polygon. Run stage=pick in interactive MATLAB first.');
end
assert(isfolder(cfg.raw_dir) || ~cfg.dasqt_make_cache, ...
    'Input directory does not exist: %s',cfg.raw_dir);
if ~exist(cfg.out_dir,'dir'), mkdir(cfg.out_dir); end
record.config = cfg;
record.matlab_version = version;
record.matlab_products = ver;
record.vendor_manifest = jsondecode(fileread(fullfile(root,'vendor','manifest.json')));
record.started_utc = char(datetime('now','TimeZone','UTC', ...
    'Format',"yyyy-MM-dd'T'HH:mm:ss'Z'"));
stamp = char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
record_file = fullfile(cfg.out_dir,['run_config_' stamp '.json']);
fid = fopen(record_file,'w');
assert(fid>=0,'Cannot write run record: %s',record_file);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
clear cleanup;
fprintf('Stage: %s\nConfiguration record: %s\n',cfg.stage,record_file);
run_pipeline(cfg);
end
