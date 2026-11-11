function cfg = workflow_config(config_file,stage)
%WORKFLOW_CONFIG Defaults reproduce the San Jose 500-channel configuration.
% JSON overrides use the same field names. Relative paths are resolved from
% the JSON file's directory; paths in defaults are relative to this project.
if nargin<1, config_file = ''; end
if nargin<2, stage = ''; end
root = fileparts(fileparts(mfilename('fullpath')));
cfg.project_root = root;
cfg.raw_dir = fullfile(root,'data');
cfg.out_dir = fullfile(root,'outputs','san_jose_500ch');
cfg.algorithm_dir = fullfile(root,'vendor','matlab');
cfg.dasqt_source = fullfile(root,'vendor','dasqt');
cfg.dasqt_python = getenv('DAS_WORKFLOW_PYTHON');
if isempty(cfg.dasqt_python)
    cfg.dasqt_python = fullfile(root,'.venv','bin','python');
end
cfg.dasqt_cache_dir = '';
cfg.stage = 'preview';
cfg.Fs = 200;
cfg.n_station = 500;
cfg.raw_channel_start = 16700;
cfg.raw_channel_first0 = 0;
cfg.channel_spacing_m = 1;
cfg.gauge_length_m = 10;
cfg.station_x = [];
cfg.n_workers = 4;
cfg.edwav_workers = 4;
cfg.segment_seconds = 600;
cfg.max_segments = 144;
cfg.selected_dates = strings(0,1);
cfg.minimum_segments_per_window = 72;
cfg.dasqt_make_cache = true;
cfg.dasqt_rebuild_cache = false;
cfg.dasqt_band = [3 30];
cfg.dasqt_butter_order = 4;
cfg.dasqt_tukey_alpha = 0.05;
cfg.dasqt_common_mode_removal = true;
cfg.edwav_band = [6 30];
cfg.edwav_frequency_resolution = 240;
cfg.edwav_noise_threshold_k_mad = 2;
cfg.edwav_noise_type = 1;
cfg.edwav_smoothing_fraction = 0.05;
cfg.edwav_window_seconds = 60;
cfg.edwav_distance_seconds = 60;
cfg.ccf_time_normalization = 'No';
cfg.ccf_frequency_normalization = 'PSD';
cfg.ccf_taper = 'No';
cfg.ccf_fft_length = 0;
cfg.ccf_frequency_decimation = 1;
cfg.ccf_reference_gather = true;
cfg.reference_channel = 1;
cfg.include_reference_autocorrelation = true;
cfg.fj_function = 'H2';
cfg.fj_window = 'No';
cfg.fj_inverse_threshold = 0.01;
cfg.attenuation_function = 'J0';
cfg.attenuation_envelope = 'No';
cfg.distance_bin_m = 0.8;
cfg.filter_velocity = [50 1000];
cfg.apply_gw_mute = false;
cfg.top_mute = [300 -0.015 16];
cfg.bottom_mute = [160 0.050 12];
cfg.mute_reference_s = 0.5;
cfg.frequency_range = [1 15];
cfg.ccf_maximum_frequency = 30;
cfg.frequency_step = 0.1;
cfg.ccf_window_half_s = 1;
cfg.fj_reliable_range = [3 12];
cfg.velocity = (100:800).';
cfg.pick_velocity_range = [140 450];
cfg.pick_seed_frequency = 10;
cfg.inspection_dates = strings(0,1);
cfg.offset_range = [];
cfg.alpha_grid = 0:0.001:0.15;

config_dir = root;
if ~isempty(config_file)
    assert(isfile(config_file),'Configuration file does not exist: %s',config_file);
    [ok,attr] = fileattrib(config_file);
    assert(ok,'Cannot resolve configuration file: %s',config_file);
    config_dir = fileparts(attr.Name);
    overrides = jsondecode(fileread(attr.Name));
    assert(isstruct(overrides) && isscalar(overrides), ...
        'Configuration must be one JSON object.');
    names = fieldnames(overrides);
    protected = {'project_root','algorithm_dir','dasqt_source'};
    for i = 1:numel(names)
        name = names{i};
        if strcmp(name,'preview_time_max_s')
            assert(~isfield(overrides,'ccf_window_half_s'), ...
                'Use ccf_window_half_s instead of preview_time_max_s.');
            cfg.ccf_window_half_s = overrides.(name);
            continue;
        end
        assert(isfield(cfg,name),'Unknown configuration field: %s',name);
        assert(~ismember(name,protected),'Internal path is fixed: %s',name);
        cfg.(name) = overrides.(name);
    end
    % Resolve only paths supplied by this JSON file. Project defaults keep
    % their original absolute paths.
    paths = {'raw_dir','out_dir','dasqt_python','dasqt_cache_dir'};
    for i = 1:numel(paths)
        name = paths{i};
        if isfield(overrides,name) && ~isempty(cfg.(name))
            value = char(cfg.(name));
            if ~startsWith(value,filesep)
                value = fullfile(config_dir,value);
            end
            cfg.(name) = value;
        end
    end
end
if ~isempty(stage), cfg.stage = char(stage); end
cfg.stage = validatestring(cfg.stage,{'edwav','ccf','preview','pick','attenuation'});
cfg.selected_dates = string(cfg.selected_dates(:));
cfg.inspection_dates = string(cfg.inspection_dates(:));
validateattributes(cfg.Fs,{'numeric'},{'scalar','finite','positive'});
validateattributes(cfg.n_station,{'numeric'},{'scalar','integer','>=',2});
validateattributes(cfg.channel_spacing_m,{'numeric'},{'scalar','finite','positive'});
validateattributes(cfg.n_workers,{'numeric'},{'scalar','integer','positive'});
validateattributes(cfg.edwav_workers,{'numeric'},{'scalar','integer','positive'});
validateattributes(cfg.raw_channel_first0,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(cfg.reference_channel,{'numeric'}, ...
    {'scalar','integer','>=',1,'<=',cfg.n_station});
validateattributes(cfg.max_segments,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(cfg.minimum_segments_per_window,{'numeric'}, ...
    {'scalar','integer','positive'});
assert(cfg.segment_seconds==600,'This workflow uses 600-s segments.');
assert(mod(cfg.segment_seconds*cfg.Fs,1)==0, ...
    'Sampling rate must give an integer number of samples per segment.');
if isempty(cfg.station_x)
    cfg.station_x = (0:cfg.n_station-1)*cfg.channel_spacing_m;
end
cfg.station_x = double(cfg.station_x(:).');
assert(numel(cfg.station_x)==cfg.n_station && ...
    all(isfinite(cfg.station_x)) && all(diff(cfg.station_x)>0), ...
    'station_x must contain n_station increasing finite positions in metres.');
cfg.velocity = double(cfg.velocity(:));
assert(numel(cfg.velocity)>=2 && all(isfinite(cfg.velocity)) && ...
    all(cfg.velocity>0) && all(diff(cfg.velocity)>0),'Invalid velocity grid.');
if isempty(cfg.offset_range), cfg.offset_range = [1 range(cfg.station_x)]; end
cfg.alpha_grid = double(cfg.alpha_grid(:).');
% JSON arrays decode to columns. The original MATLAB functions expect rows
% for bounds and mute tuples.
row_fields = {'dasqt_band','edwav_band','filter_velocity','top_mute', ...
    'bottom_mute','frequency_range','pick_velocity_range','offset_range'};
for i = 1:numel(row_fields)
    name = row_fields{i};
    cfg.(name) = double(cfg.(name)(:).');
end
for name = {'dasqt_band','edwav_band','frequency_range'}
    bounds = cfg.(name{1});
    assert(numel(bounds)==2 && all(isfinite(bounds)) && ...
        bounds(1)>0 && bounds(1)<bounds(2) && bounds(2)<cfg.Fs/2, ...
        'Invalid frequency bounds: %s',name{1});
end
validateattributes(cfg.ccf_maximum_frequency,{'numeric'}, ...
    {'scalar','finite','positive','<',cfg.Fs/2});
assert(cfg.frequency_range(2)<=cfg.dasqt_band(2) && ...
    cfg.ccf_maximum_frequency>=cfg.frequency_range(2) && ...
    cfg.ccf_maximum_frequency<=cfg.dasqt_band(2), ...
    'CCF maximum frequency must cover the analysis band and stay within the preprocessing upper bound.');
assert(cfg.edwav_band(1)>=cfg.dasqt_band(1) && ...
    cfg.edwav_band(2)<=cfg.dasqt_band(2), ...
    'EDWav band must lie inside the preprocessing band.');
assert(numel(cfg.top_mute)==3 && numel(cfg.bottom_mute)==3 && ...
    cfg.top_mute(1)>0 && cfg.bottom_mute(1)>0 && ...
    cfg.top_mute(3)>0 && cfg.bottom_mute(3)>0,'Invalid mute tuples.');
assert(numel(cfg.filter_velocity)==2 && all(cfg.filter_velocity>0) && ...
    cfg.filter_velocity(1)<cfg.filter_velocity(2),'Invalid velocity filter.');
validateattributes(cfg.frequency_step,{'numeric'},{'scalar','finite','positive'});
validateattributes(cfg.ccf_window_half_s,{'numeric'}, ...
    {'scalar','finite','positive','<=',cfg.segment_seconds/2});
cfg.fj_reliable_range = double(cfg.fj_reliable_range(:).');
assert(numel(cfg.fj_reliable_range)==2 && ...
    cfg.fj_reliable_range(1)>=cfg.frequency_range(1) && ...
    cfg.fj_reliable_range(1)<cfg.fj_reliable_range(2) && ...
    cfg.fj_reliable_range(2)<=cfg.frequency_range(2), ...
    'Reliable frequency range must lie inside the analysis range.');
assert(islogical(cfg.apply_gw_mute) || ...
    (isnumeric(cfg.apply_gw_mute) && isscalar(cfg.apply_gw_mute) && ...
    ismember(cfg.apply_gw_mute,[0 1])),'apply_gw_mute must be boolean.');
cfg.apply_gw_mute = logical(cfg.apply_gw_mute);
assert(cfg.ccf_frequency_decimation==1, ...
    'FD must remain 1 for reconstruction of lag-domain CCF and mute.');
assert(cfg.ccf_fft_length==0 || cfg.ccf_fft_length>=cfg.segment_seconds*cfg.Fs, ...
    'FFT length must be zero or at least one correlation window.');
if isempty(cfg.dasqt_cache_dir)
    cfg.dasqt_cache_dir = fullfile(cfg.out_dir,'dasqt_cache');
end
end
