function run_pipeline(cfg)
%RUN_PIPELINE Portable form of the authoritative SJDAS MATLAB observation flow.
% Scientific processing follows MCCFJFLOW2Manual; paths and parameters come
% from workflow_config. See docs/PROCESSING.md and vendor/manifest.json.
root = cfg.project_root;
raw_dir = cfg.raw_dir;
out_dir = cfg.out_dir;
algorithm_dir = cfg.algorithm_dir;
dasqt_source = cfg.dasqt_source;
raw_channel_start = cfg.raw_channel_start;
dasqt_script = fullfile(root,'python','prepare_dasqt.py');
if ~exist(out_dir,'dir'), mkdir(out_dir); end
addpath(algorithm_dir,'-begin');
Fs = cfg.Fs;
station_x = cfg.station_x;
n_workers = cfg.n_workers;
edwav_workers = cfg.edwav_workers;
segment_seconds = cfg.segment_seconds;
max_segments = cfg.max_segments;
selected_dates = cfg.selected_dates;
minimum_segments_per_window = cfg.minimum_segments_per_window;
dasqt_make_cache = cfg.dasqt_make_cache;
dasqt_rebuild_cache = cfg.dasqt_rebuild_cache;
dasqt_python = cfg.dasqt_python;
dasqt_band = cfg.dasqt_band;
dasqt_butter_order = cfg.dasqt_butter_order;
dasqt_tukey_alpha = cfg.dasqt_tukey_alpha;
dasqt_common_mode_removal = cfg.dasqt_common_mode_removal;
raw_channel_first0 = cfg.raw_channel_first0;
n_station = cfg.n_station;
channel_spacing_m = cfg.channel_spacing_m;
gauge_length_m = cfg.gauge_length_m;
edwav_band = cfg.edwav_band;
edwav_frequency_resolution = cfg.edwav_frequency_resolution;
edwav_noise_threshold_k_mad = cfg.edwav_noise_threshold_k_mad;
edwav_noise_type = cfg.edwav_noise_type;
edwav_smoothing_fraction = cfg.edwav_smoothing_fraction;
edwav_window_seconds = cfg.edwav_window_seconds;
edwav_distance_seconds = cfg.edwav_distance_seconds;
ccf_time_normalization = cfg.ccf_time_normalization;
ccf_frequency_normalization = cfg.ccf_frequency_normalization;
ccf_taper = cfg.ccf_taper;
ccf_fft_length = cfg.ccf_fft_length;
ccf_frequency_decimation = cfg.ccf_frequency_decimation;
fj_function = cfg.fj_function;
fj_window = cfg.fj_window;
fj_inverse_threshold = cfg.fj_inverse_threshold;
attenuation_function = cfg.attenuation_function;
attenuation_envelope = cfg.attenuation_envelope;
distance_bin_m = cfg.distance_bin_m;
filter_velocity = cfg.filter_velocity;
top_mute = cfg.top_mute;
bottom_mute = cfg.bottom_mute;
mute_reference_s = cfg.mute_reference_s;
frequency_range = cfg.frequency_range;
frequency_step = cfg.frequency_step;
apply_gw_mute = cfg.apply_gw_mute;
velocity = cfg.velocity;
pick_velocity_range = cfg.pick_velocity_range;
pick_seed_frequency = cfg.pick_seed_frequency;
ccf_reference_gather = cfg.ccf_reference_gather;
reference_channel = cfg.reference_channel;
include_reference_autocorrelation = cfg.include_reference_autocorrelation;
inspection_dates = cfg.inspection_dates;
offset_range = cfg.offset_range;
alpha_grid = cfg.alpha_grid;
dasqt_cache_dir = cfg.dasqt_cache_dir;
stop_after_edwav_record = strcmp(cfg.stage,'edwav');
stop_after_composite = strcmp(cfg.stage,'preview');
manual_pick_mask = strcmp(cfg.stage,'pick');

%% 2. DASQt cache inventory and EDWav screening
if dasqt_make_cache
    ensure_dasqt_cache(raw_dir,dasqt_cache_dir,dasqt_python,dasqt_script, ...
        raw_channel_first0,n_station,Fs,dasqt_source,channel_spacing_m,gauge_length_m, ...
        segment_seconds,max_segments,dasqt_band, ...
        dasqt_butter_order,dasqt_tukey_alpha,dasqt_common_mode_removal, ...
        dasqt_rebuild_cache);
end
cache_files = dir(fullfile(dasqt_cache_dir,'segments','segment_*.mat'));
[~,order] = sort({cache_files.name}); cache_files = cache_files(order);
if max_segments>0
    cache_files = cache_files(1:min(numel(cache_files),max_segments));
end
assert(~isempty(cache_files),'DASQt cache中没有segment MAT文件。');
file_paths = fullfile({cache_files.folder},{cache_files.name});
file_paths = string(file_paths(:));
nseg = numel(file_paths);
segment_start = strings(nseg,1);
raw_valid = false(nseg,n_station);
proxy = nan(nseg,n_station);
preview_seconds = 60;
preview_samples = preview_seconds*Fs;
preview_blocks_per_segment = segment_seconds/preview_seconds;
record_rms_60s = nan(nseg*preview_blocks_per_segment,n_station,'single');
for iseg = 1:nseg
    A = load(file_paths(iseg),'start_time','raw_valid');
    segment_start(iseg) = string(A.start_time);
    raw_valid(iseg,:) = logical(A.raw_valid(:)).';
end
file_day = extractBefore(segment_start,11);
all_dates = unique(file_day,'stable');
segment_samples = segment_seconds*Fs;

fprintf('DASQt cache: %d x %d s, target raw channels %d--%d.\n', ...
    nseg,segment_seconds,raw_channel_start+raw_channel_first0, ...
    raw_channel_start+raw_channel_first0+n_station-1);

edwav_cache_config.segment_paths = file_paths;
edwav_cache_config.segment_inventory = [[cache_files.bytes].', ...
    [cache_files.datenum].'];
edwav_cache_config.raw_valid = raw_valid;
edwav_cache_config.Fs = Fs;
edwav_cache_config.station_x = station_x;
edwav_cache_config.segment_seconds = segment_seconds;
edwav_cache_config.dasqt_band = dasqt_band;
edwav_cache_config.dasqt_butter_order = dasqt_butter_order;
edwav_cache_config.dasqt_tukey_alpha = dasqt_tukey_alpha;
edwav_cache_config.dasqt_common_mode_removal = dasqt_common_mode_removal;
edwav_cache_config.edwav_band = edwav_band;
edwav_cache_config.edwav_frequency_resolution = edwav_frequency_resolution;
edwav_cache_config.edwav_noise_threshold_k_mad = edwav_noise_threshold_k_mad;
edwav_cache_config.edwav_noise_type = edwav_noise_type;
edwav_cache_config.edwav_smoothing_fraction = edwav_smoothing_fraction;
edwav_cache_config.edwav_window_seconds = edwav_window_seconds;
edwav_cache_config.edwav_distance_seconds = edwav_distance_seconds;
edwav_cache_file = fullfile(out_dir,'edwav_screening.mat');
reuse_edwav = false;
if isfile(edwav_cache_file)
    cached_edwav = load(edwav_cache_file,'edwav_cache_config');
    if isfield(cached_edwav,'edwav_cache_config') && ...
            isequaln(cached_edwav.edwav_cache_config,edwav_cache_config)
        cached_edwav = load(edwav_cache_file,'proxy','record_rms_60s');
        reuse_edwav = isfield(cached_edwav,'proxy') && ...
            isfield(cached_edwav,'record_rms_60s');
    end
end

if reuse_edwav
    proxy = cached_edwav.proxy;
    record_rms_60s = cached_edwav.record_rms_60s;
    fprintf('复用匹配的 EDWav 筛选缓存：%s\n',edwav_cache_file);
else
    load_edwav_class_local(algorithm_dir);
    proxy_cell = cell(nseg,1);
    record_rms_cell = cell(nseg,1);
    pool = gcp('nocreate');
    if isempty(pool) || pool.NumWorkers~=edwav_workers
        if ~isempty(pool), delete(pool); end
        parpool('local',edwav_workers);
    end
    parfor iseg = 1:nseg
    load_edwav_class_local(algorithm_dir);
    A = load(file_paths(iseg),'wave');
    wave = double(A.wave);
    assert(isequal(size(wave),[segment_samples,n_station]), ...
        'DASQt cache尺寸错误：%s',file_paths(iseg));
    block_wave = reshape(wave,preview_samples, ...
        preview_blocks_per_segment,n_station);
    rms_row = single(squeeze(sqrt(mean(block_wave.^2,1))));
    proxy_row = nan(1,n_station);
    for ich = 1:n_station
        if ~raw_valid(iseg,ich), continue; end
        result = EDWav.evaluate_sliding(wave(:,ich),Fs, ...
            'FB',edwav_band,'FR',edwav_frequency_resolution, ...
            'NT',edwav_noise_type,'SF',edwav_smoothing_fraction, ...
            'NW',edwav_window_seconds,'DW',edwav_distance_seconds);
        proxy_row(ich) = result(1);
    end
        proxy_cell{iseg} = proxy_row;
        record_rms_cell{iseg} = rms_row;
    end
    proxy = vertcat(proxy_cell{:});
    record_rms_60s = vertcat(record_rms_cell{:});
    for iseg = 1:nseg
        fprintf('EDWav %3d/%3d: %s\n',iseg,nseg,segment_start(iseg));
    end
end

eligible = raw_valid & isfinite(proxy) & proxy>0;
log_proxy = nan(size(proxy)); log_proxy(eligible) = log(proxy(eligible));
center = median(log_proxy,1,'omitnan');
spread = median(abs(log_proxy-center),1,'omitnan');
threshold = center + edwav_noise_threshold_k_mad*spread;
keep = eligible & log_proxy<=threshold;

fprintf('EDWav保留：%d / %d 个有效台站片段（%.1f%%）\n', ...
    sum(keep(:)),sum(raw_valid(:)),100*sum(keep(:))/sum(raw_valid(:)));

save(fullfile(out_dir,'edwav_screening.mat'), ...
    'segment_start','file_paths','file_day','raw_valid','proxy', ...
    'eligible','log_proxy','keep','center','spread','threshold', ...
    'edwav_cache_config','record_rms_60s', ...
    'Fs','station_x','segment_seconds','dasqt_cache_dir', ...
    'dasqt_band','dasqt_butter_order','dasqt_tukey_alpha', ...
    'dasqt_common_mode_removal','channel_spacing_m','gauge_length_m', ...
    'edwav_band','edwav_frequency_resolution', ...
    'edwav_noise_threshold_k_mad','edwav_noise_type', ...
    'edwav_smoothing_fraction','edwav_window_seconds', ...
    'edwav_distance_seconds', ...
    '-v7.3');
write_edwav_csv(fullfile(out_dir,'edwav_segments.csv'), ...
    segment_start,proxy,raw_valid,eligible,keep);

segment_keep_any_pair = sum(keep,2)>=2;
segment_keep_all_stations = sum(keep,2)==n_station;
segment_keep_fraction = sum(keep,2)/n_station;
record_time_hours = ((0:size(record_rms_60s,1)-1)*preview_seconds)/3600;
record_duration_hours = size(record_rms_60s,1)*preview_seconds/3600;

if n_station==500
    record_preview_file = fullfile(out_dir,'sjdas_500ch_24h_record_preview.mat');
    record_preview_plot = fullfile(out_dir,'sjdas_500ch_24h_record_edwav.png');
else
    record_preview_file = fullfile(out_dir, ...
        sprintf('sjdas_%dch_record_preview.mat',n_station));
    record_preview_plot = fullfile(out_dir, ...
        sprintf('sjdas_%dch_record_edwav.png',n_station));
end
save(record_preview_file, ...
    'record_rms_60s','record_time_hours','preview_seconds', ...
    'segment_start','keep','raw_valid','eligible','proxy','threshold', ...
    'segment_keep_any_pair','segment_keep_all_stations','segment_keep_fraction', ...
    'station_x','Fs','channel_spacing_m','gauge_length_m', ...
    'dasqt_cache_dir','edwav_band','edwav_noise_threshold_k_mad', ...
    '-v7.3');

fig_record = figure('Color','w','Position',[80 60 1450 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
ax = nexttile;
record_db = 20*log10(double(record_rms_60s)+eps);
imagesc(ax,record_time_hours,station_x,record_db.');
axis(ax,'xy'); colormap(ax,jet); colorbar(ax);
finite_db = record_db(isfinite(record_db));
if ~isempty(finite_db)
    db_lim = prctile(finite_db,[2 98]);
    if all(isfinite(db_lim)) && db_lim(1)<db_lim(2), caxis(ax,db_lim); end
end
xlabel(ax,'Time (h)'); ylabel(ax,'Channel position (m)');
if n_station==500
    record_title = 'DASQt-preprocessed 500-channel, 24 h record (60 s RMS preview)';
else
    record_title = sprintf('DASQt-preprocessed %d-channel, %.3g h record (60 s RMS preview)', ...
        n_station,record_duration_hours);
end
title(ax,record_title);
ax = nexttile;
imagesc(ax,1:nseg,station_x,keep.');
axis(ax,'xy'); caxis(ax,[0 1]); colormap(ax,gray); colorbar(ax);
xlabel(ax,'600 s segment'); ylabel(ax,'Channel position (m)');
title(ax,sprintf('EDWav keep mask: %d/%d segments have at least two retained channels', ...
    sum(segment_keep_any_pair),nseg));
exportgraphics(fig_record,record_preview_plot,'Resolution',250);

if n_station==500
    fprintf(['500道24 h记录预览：%s\n' ...
        '至少2道通过EDWav：%d/%d个600 s片段（%.2f h）；500道全部通过：%d/%d。\n'], ...
        record_preview_plot,sum(segment_keep_any_pair),nseg, ...
        sum(segment_keep_any_pair)*segment_seconds/3600, ...
        sum(segment_keep_all_stations),nseg);
else
    fprintf(['%d道记录预览：%s\n' ...
        '至少2道通过EDWav：%d/%d个600 s片段（%.2f h）；%d道全部通过：%d/%d。\n'], ...
        n_station,record_preview_plot,sum(segment_keep_any_pair),nseg, ...
        sum(segment_keep_any_pair)*segment_seconds/3600, ...
        n_station,sum(segment_keep_all_stations),nseg);
end

if stop_after_edwav_record
    fprintf('本次按要求停在%d道记录和EDWav筛选，未进入CCF/F-J。\n',n_station);
    return;
end

% 每日筛选概览
daily_keep = nan(n_station,numel(all_dates));
daily_count = zeros(numel(all_dates),1);
for id = 1:numel(all_dates)
    ids = find(file_day==all_dates(id));
    raw_day = raw_valid(ids,:);
    keep_day = keep(ids,:);
    n_raw = sum(raw_day,1);
    daily_keep(:,id) = sum(keep_day,1)./max(n_raw,1);
    daily_keep(n_raw==0,id) = nan;
    daily_count(id) = sum(sum(keep_day,2)>=2);
end

date_ticks = unique(round(linspace(1,numel(all_dates),7)));
fig = figure('Color','w','Position',[100 80 1250 650]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

ax = nexttile;
imagesc(1:numel(all_dates),station_x,daily_keep); axis xy;
colormap(ax,jet); colorbar; caxis([0 1]);
ylabel('Station position (m)');
title('(a) EDWav retained fraction');
ax.XTick = date_ticks;
ax.XTickLabel = [];

ax = nexttile;
plot(1:numel(all_dates),daily_count,'k-','LineWidth',1.1);
grid on;
xlabel('Date');
ylabel('Retained 600-s segments');
title('(b) Daily retained segments');
ax.XTick = date_ticks;
ax.XTickLabel = all_dates(date_ticks);

exportgraphics(fig,fullfile(out_dir,'EDWav_screening.png'),'Resolution',300);

%% 3. 建立24 h观测窗口
dates = strings(0,1);
file_ids_24h = cell(0,1);
if isempty(selected_dates)
    candidate_dates = all_dates;
else
    candidate_dates = string(selected_dates(:));
end
for id = 1:numel(candidate_dates)
    ids = find(file_day==candidate_dates(id));
    enough_segments = numel(ids)>=minimum_segments_per_window;
    has_pair = any(sum(keep(ids,:),2)>=2);
    if enough_segments && has_pair
        dates(end+1,1) = candidate_dates(id); %#ok<SAGROW>
        file_ids_24h{end+1,1} = ids; %#ok<SAGROW>
    end
end

frequency = (frequency_range(1):frequency_step: ...
    (frequency_range(2)-frequency_step/2)).';

p.Fs = Fs;
p.station_x = station_x;
p.segment_samples = segment_samples;
p.segment_inventory = [[cache_files.bytes].',[cache_files.datenum].'];
p.channel_spacing_m = channel_spacing_m;
p.gauge_length_m = gauge_length_m;
p.dasqt_cache_dir = dasqt_cache_dir;
p.dasqt_band = dasqt_band;
p.dasqt_butter_order = dasqt_butter_order;
p.dasqt_tukey_alpha = dasqt_tukey_alpha;
p.dasqt_common_mode_removal = dasqt_common_mode_removal;
p.raw_channel_first0 = raw_channel_first0;
p.n_station = n_station;
p.segment_seconds = segment_seconds;
p.edwav_band = edwav_band;
p.edwav_frequency_resolution = edwav_frequency_resolution;
p.edwav_noise_threshold_k_mad = edwav_noise_threshold_k_mad;
p.edwav_noise_type = edwav_noise_type;
p.edwav_smoothing_fraction = edwav_smoothing_fraction;
p.edwav_window_seconds = edwav_window_seconds;
p.edwav_distance_seconds = edwav_distance_seconds;

p.ccf_time_normalization = ccf_time_normalization;
p.ccf_frequency_normalization = ccf_frequency_normalization;
p.ccf_taper = ccf_taper;
p.ccf_fft_length = ccf_fft_length;
p.ccf_frequency_decimation = ccf_frequency_decimation;
p.ccf_reference_gather = ccf_reference_gather;
p.reference_channel = reference_channel;
p.include_reference_autocorrelation = include_reference_autocorrelation;

p.fj_function = fj_function;
p.fj_window = fj_window;
p.fj_inverse_threshold = fj_inverse_threshold;
p.attenuation_function = attenuation_function;
p.attenuation_envelope = attenuation_envelope;

p.distance_bin_m = distance_bin_m;
p.filter_velocity = filter_velocity;
p.apply_gw_mute = apply_gw_mute;
p.top_mute = top_mute;
p.bottom_mute = bottom_mute;
p.mute_reference_s = mute_reference_s;

p.frequency_range = frequency_range;
p.ccf_maximum_frequency = cfg.ccf_maximum_frequency;
p.frequency_step = frequency_step;
p.frequency = frequency;
p.velocity = velocity;
p.ccf_window_half_s = cfg.ccf_window_half_s;
p.fj_reliable_range = cfg.fj_reliable_range;

p.pick_velocity_range = pick_velocity_range;
p.pick_seed_frequency = pick_seed_frequency;

p.offset_range = offset_range;
p.alpha_grid = alpha_grid;

%% 4. 先计算并缓存24 h CCF
% CCF缓存位于stack_bin、filtering和mute之前。
%
% 以下参数变化 -> 自动重新计算CCF：
%   EDWav keep
%   NT / NF / TP / FL / FD / FM
%
% 以下参数变化 -> 不重新计算CCF：
%   distance_bin
%   filtering
%   mute
%   F-J Fun / Win
%   ridge / manual polygon mask
%   attenuation
%
% 后一类参数修改后，直接读取CCF缓存重新提取即可。

cache_dir = fullfile(out_dir,'ccf_cache');
if ~exist(cache_dir,'dir'), mkdir(cache_dir); end

ccf_cache_files = fullfile(cache_dir,"ccf_24h_"+dates+".mat");

pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers~=n_workers
    if ~isempty(pool), delete(pool); end
    parpool('local',n_workers);
end

%% 5. 补齐全部日期的CCF缓存
cache_ok = false(numel(dates),1);

fprintf('开始生成全部%d个24 h CCF缓存；已有缓存会自动跳过。\n', ...
    numel(dates));

parfor id = 1:numel(dates)
    cache_ok(id) = build_24h_ccf( ...
        file_ids_24h{id},file_paths,keep,p,ccf_cache_files(id));
end
reference_valid_segments = sum(keep(:,reference_channel));
fprintf('固定参考道 ch%d 可参与CCF：%d/%d个600 s片段（%.2f h）；0 m自相关保留在%d-trace gather但不进入F-J。\n', ...
    raw_channel_start+raw_channel_first0+reference_channel-1,reference_valid_segments,nseg, ...
    reference_valid_segments*segment_seconds/3600,n_station);

if strcmp(cfg.stage,'ccf')
    fprintf('CCF cache stage complete: %s\n',cache_dir);
    return;
end

%% 6. 先计算全部日期的F-J频散谱
% 保留mCCFJ.transform得到的原始F-J幅值，不做逐频率归一化。
% 综合频散谱采用所有有效日期原始F-J幅值的逐点平均。

n_velocity = numel(velocity);
n_frequency = numel(frequency);
n_date = numel(dates);

daily_spectrum = nan(n_velocity,n_frequency,n_date,'single');
daily_ridge_velocity = nan(n_frequency,n_date);
pair_window_count = zeros(n_date,1);
fj_ok = false(n_date,1);

fprintf('开始计算全部日期的F-J频散谱，用于建立综合频散谱。\n');

parfor id = 1:n_date

    if ~cache_ok(id)
        continue;
    end

    [spectrum_day,ridge_day,pair_count_day] = ...
        dispersion_from_ccf(ccf_cache_files(id),p);

    if ~isempty(spectrum_day)

        daily_spectrum(:,:,id) = single(spectrum_day);
        daily_ridge_velocity(:,id) = ridge_day;
        pair_window_count(id) = pair_count_day;
        fj_ok(id) = true;
    end
end

valid_date = cache_ok & fj_ok & pair_window_count>0;

dates = dates(valid_date);
ccf_cache_files = ccf_cache_files(valid_date);
daily_spectrum = daily_spectrum(:,:,valid_date);
daily_ridge_velocity = daily_ridge_velocity(:,valid_date);
pair_window_count = pair_window_count(valid_date);

if isempty(dates)
    error('没有可用于综合频散谱的有效日期。');
end

%% 7. 综合全部日期的频散谱
% 不归一化：直接对全部有效日期的原始F-J幅值求平均。
composite_spectrum = mean(daily_spectrum,3,'omitnan');
composite_spectrum = double(composite_spectrum);

% 综合频散谱用原来的findpeaks趋势追踪拾取ridge。
% 是否归一化不会改变单个频率列内部峰值的位置。
valid_velocity = ...
    velocity>=pick_velocity_range(1) & ...
    velocity<=pick_velocity_range(2);

pick_spectrum = composite_spectrum;
pick_spectrum(~valid_velocity,:) = 0;

[~,seed] = min(abs(frequency-pick_seed_frequency));

first_velocity = find(valid_velocity,1,'first');
last_velocity = find(valid_velocity,1,'last');

composite_ridge_index = pickRidgeAlongTrend( ...
    pick_spectrum,seed,first_velocity,last_velocity);

composite_ridge_velocity = velocity(composite_ridge_index);

if n_station==500
    composite_file = fullfile(out_dir,'mccfj_composite_500ch_24h.mat');
else
    composite_file = fullfile(out_dir, ...
        sprintf('mccfj_composite_%dch.mat',n_station));
end
save(composite_file, ...
    'dates','frequency','velocity','daily_spectrum', ...
    'daily_ridge_velocity','pair_window_count', ...
    'composite_spectrum','composite_ridge_velocity', ...
    'keep','raw_valid','reference_valid_segments','p','-v7.3');

plot_default_preview(ccf_cache_files(1),p, ...
    frequency,velocity,composite_spectrum,composite_ridge_velocity,out_dir);

if stop_after_composite
    fprintf(['已完成%d道CCF和综合F-J预览，暂不进入人工polygon mask。\n' ...
        '首次选mask使用stage=pick；已有mask后使用stage=attenuation。\n'], ...
        n_station);
    return;
end

%% 8. 建立综合polygon mask
manual_mask_file = fullfile(out_dir,'manual_mask_polygon.mat');

if manual_pick_mask

    fprintf('\n开始手动拾取综合mask：\n');
    fprintf('  左键：增加顶点\n');
    fprintf('  右键：撤回上一个顶点\n');
    fprintf('  回车：闭合polygon并继续\n\n');

    [mask_polygon_frequency,mask_polygon_velocity, ...
        composite_mask_low_velocity,composite_mask_high_velocity, ...
        composite_manual_mask,mask_figure] = ...
        pickManualPolygonMask( ...
            frequency,velocity,composite_spectrum, ...
            composite_ridge_velocity);

    % 记录这个mask建立时对应的综合ridge。
    % 以后manual_pick_mask=false复用mask时，也沿用同一个参考ridge。
    mask_reference_ridge_velocity = composite_ridge_velocity;

    save(manual_mask_file, ...
        'mask_polygon_frequency','mask_polygon_velocity', ...
        'composite_mask_low_velocity','composite_mask_high_velocity', ...
        'composite_manual_mask','mask_reference_ridge_velocity', ...
        'composite_spectrum','frequency','velocity','dates','-v7.3');

    fprintf('新的手动mask已保存：%s\n',manual_mask_file);

else

    if ~isfile(manual_mask_file)
        error(['manual_pick_mask=false，但没有找到已保存的mask文件：\n' ...
            '%s\n请先将manual_pick_mask设为true运行一次。'],manual_mask_file);
    end

    M = load(manual_mask_file, ...
        'mask_polygon_frequency','mask_polygon_velocity', ...
        'composite_mask_low_velocity','composite_mask_high_velocity', ...
        'composite_manual_mask','mask_reference_ridge_velocity', ...
        'frequency','velocity');

    % 防止把其它频率/速度设置下的旧mask误用到当前计算。
    if ~isequaln(M.frequency(:),frequency(:)) || ...
            ~isequaln(M.velocity(:),velocity(:))
        error(['已有manual mask的frequency/velocity网格与当前程序不同。\n' ...
            '请将manual_pick_mask设为true重新拾取。']);
    end

    mask_polygon_frequency = M.mask_polygon_frequency;
    mask_polygon_velocity = M.mask_polygon_velocity;
    composite_mask_low_velocity = M.composite_mask_low_velocity;
    composite_mask_high_velocity = M.composite_mask_high_velocity;
    composite_manual_mask = M.composite_manual_mask;

    if isfield(M,'mask_reference_ridge_velocity')
        mask_reference_ridge_velocity = M.mask_reference_ridge_velocity;
    else
        % 兼容较早保存的mask文件。
        mask_reference_ridge_velocity = composite_ridge_velocity;
    end

    % 即使不重新拾取，也把旧mask叠加到当前综合原始F-J底图上检查。
    mask_figure = showCompositeMask( ...
        frequency,velocity,composite_spectrum, ...
        composite_ridge_velocity, ...
        mask_polygon_frequency,mask_polygon_velocity, ...
        composite_mask_low_velocity,composite_mask_high_velocity);

    fprintf('已读取已有手动mask：%s\n',manual_mask_file);
end

manual_mask_png = fullfile(out_dir,'composite_manual_mask.png');
exportgraphics(mask_figure,manual_mask_png,'Resolution',300);

fprintf('综合原始F-J频散谱及mask图：%s\n',manual_mask_png);

%% 9. 用手动mask逐日期提取衰减
% 人工polygon不要求精确画到frequency_range左右端点。
%
% polygon覆盖到的频率范围：严格采用人工拾取的上下边界。
%
% polygon没有覆盖到的左右端：
%   保持最近人工边界相对于composite ridge的上下偏移，
%   沿composite ridge自动延伸到完整frequency_range。
%
% 然后对每个日期：
%   delta_v(f) = daily_ridge(f) - composite_ridge(f)
%
% 将完整综合mask的上下边界同时平移delta_v(f)，
% 因此人工决定mask形状，每天只根据实际ridge做速度方向微调。

alpha = nan(n_frequency,numel(dates));
phase_velocity = daily_ridge_velocity;
daily_mask_point_count = zeros(numel(dates),1);
attenuation_ok = false(numel(dates),1);

fprintf('开始根据手动polygon mask提取全部%d个日期的衰减。\n',numel(dates));

parfor id = 1:numel(dates)

    [alpha_day,mask_point_count,ok] = ...
        attenuation_from_manual_mask( ...
        ccf_cache_files(id),p, ...
            composite_mask_low_velocity, ...
            composite_mask_high_velocity, ...
            mask_reference_ridge_velocity);

    alpha(:,id) = alpha_day;
    daily_mask_point_count(id) = mask_point_count;
    attenuation_ok(id) = ok;
end

valid_result = attenuation_ok & any(isfinite(alpha),1).';

dates = dates(valid_result);
alpha = alpha(:,valid_result);
phase_velocity = phase_velocity(:,valid_result);
pair_window_count = pair_window_count(valid_result);
daily_mask_point_count = daily_mask_point_count(valid_result);
daily_spectrum = daily_spectrum(:,:,valid_result);

% 给后续反演统一的输入字段名：频率 x 日期。
% 同时保留上面的原始字段，便于继续画图和追溯处理流程。
alpha_mat = alpha;
frequency_hz = frequency;
t_labels = cellstr(dates);
phase_velocity_mps = phase_velocity;
alpha_is_absolute = true;

%% 10. 保存和绘制最终时间结果
save(fullfile(out_dir,'edwav_mccfj_attenuation_manual_mask_24h.mat'), ...
    'dates','frequency','alpha','phase_velocity','pair_window_count', ...
    'daily_mask_point_count','composite_spectrum', ...
    'composite_ridge_velocity','mask_polygon_frequency', ...
    'mask_polygon_velocity','composite_mask_low_velocity', ...
    'composite_mask_high_velocity','composite_manual_mask', ...
    'mask_reference_ridge_velocity','manual_pick_mask','inspection_dates', ...
    'alpha_mat','frequency_hz','t_labels','phase_velocity_mps', ...
    'alpha_is_absolute', ...
    'keep','raw_valid','Fs','station_x','distance_bin_m', ...
    'filter_velocity','top_mute','bottom_mute','frequency_range', ...
    'velocity','pick_velocity_range','offset_range','alpha_grid','p','-v7.3');

finite_alpha = alpha(isfinite(alpha));

if isempty(finite_alpha)
    error('衰减结果为空。');
end

color_limit = prctile(finite_alpha,[1 99]);

date_ticks = unique(round(linspace(1,numel(dates),7)));

fig = figure('Color','w','Position',[80 80 1320 520]);
imagesc(1:numel(dates),frequency,alpha);
axis xy tight;
colormap(jet);
caxis(color_limit);
colorbar;

ax = gca;
ax.XTick = date_ticks;
ax.XTickLabel = dates(date_ticks);

xlabel('Date');
ylabel('Frequency (Hz)');
title('mCCFJ apparent attenuation, manual adaptive mask, 24 h CCF');

exportgraphics(fig, ...
    fullfile(out_dir,'mccfj_attenuation_manual_mask_24h.png'), ...
    'Resolution',300);

%% 11. 单独检查指定日期的F-J频散谱、当天mask和衰减
if ~isempty(inspection_dates)

    inspection_id = find(ismember(dates,inspection_dates));

    missing_dates = inspection_dates(~ismember(inspection_dates,dates));
    for ii = 1:numel(missing_dates)
        fprintf('检查日期 %s 没有有效最终结果，跳过。\n',missing_dates(ii));
    end

    if ~isempty(inspection_id)

        n_inspect = numel(inspection_id);

        fig_check = figure( ...
            'Color','w', ...
            'Position',[80 40 1450,max(420,380*n_inspect)]);

        tiledlayout(n_inspect,2, ...
            'TileSpacing','compact', ...
            'Padding','compact');

        for ii = 1:n_inspect

            id = inspection_id(ii);
            date_label = dates(id);

            spectrum_day = double(daily_spectrum(:,:,id));

            delta_velocity = ...
                phase_velocity(:,id)-mask_reference_ridge_velocity(:);

            delta_velocity(~isfinite(delta_velocity)) = 0;

            daily_low = ...
                composite_mask_low_velocity(:)+delta_velocity;

            daily_high = ...
                composite_mask_high_velocity(:)+delta_velocity;

            daily_low = max(daily_low,min(velocity));
            daily_high = min(daily_high,max(velocity));

            % ----- 当天原始F-J频散谱 + 实际mask -----
            ax = nexttile;

            imagesc(ax,frequency,velocity,spectrum_day);
            axis(ax,'xy');
            colormap(ax,jet);
            colorbar(ax);

            finite_spec = spectrum_day(isfinite(spectrum_day));
            if ~isempty(finite_spec)
                spec_limit = prctile(finite_spec,99.5);
                if isfinite(spec_limit) && spec_limit>0
                    caxis(ax,[0 spec_limit]);
                end
            end

            hold(ax,'on');

            plot(ax,frequency,phase_velocity(:,id), ...
                'k-','LineWidth',1.3);

            plot(ax,frequency,daily_low, ...
                'w-','LineWidth',1.5);

            plot(ax,frequency,daily_high, ...
                'w-','LineWidth',1.5);

            xlim(ax,frequency_range);
            ylim(ax,[velocity(1) min(600,velocity(end))]);

            xlabel(ax,'Frequency (Hz)');
            ylabel(ax,'Phase velocity (m/s)');

            title(ax,sprintf('%s: raw F-J spectrum and daily mask', ...
                date_label),'FontWeight','normal');

            % ----- 当天衰减 -----
            ax = nexttile;

            plot(ax,frequency,alpha(:,id), ...
                'k-','LineWidth',1.5);

            grid(ax,'on');
            xlim(ax,frequency_range);

            xlabel(ax,'Frequency (Hz)');
            ylabel(ax,'Attenuation (1/m)');

            title(ax,sprintf('%s: extracted attenuation', ...
                date_label),'FontWeight','normal');
        end

        inspection_png = ...
            fullfile(out_dir,'inspection_dates_fj_mask_alpha.png');

        exportgraphics(fig_check,inspection_png,'Resolution',300);

        fprintf('指定日期检查图：%s\n',inspection_png);
    end
end

fprintf('完成：%s\n',out_dir);

end % run_pipeline

%% 先计算一个24 h窗口的500-trace参考道CCF并保存紧凑CCF
function ok = build_24h_ccf(ids,file_paths,keep,p,cache_file)

% 缓存只依赖互相关阶段的设置；参数一致才复用。
cache_config.Fs = p.Fs;
cache_config.station_x = p.station_x;
cache_config.segment_samples = p.segment_samples;
cache_config.segment_inventory = p.segment_inventory(ids,:);
cache_config.maximum_frequency = p.ccf_maximum_frequency;

cache_config.time_normalization = p.ccf_time_normalization;
cache_config.frequency_normalization = p.ccf_frequency_normalization;
cache_config.taper = p.ccf_taper;
cache_config.fft_length = p.ccf_fft_length;
cache_config.frequency_decimation = p.ccf_frequency_decimation;
cache_config.channel_spacing_m = p.channel_spacing_m;
cache_config.gauge_length_m = p.gauge_length_m;
cache_config.dasqt_cache_dir = char(p.dasqt_cache_dir);
cache_config.dasqt_band = p.dasqt_band;
cache_config.dasqt_butter_order = p.dasqt_butter_order;
cache_config.dasqt_tukey_alpha = p.dasqt_tukey_alpha;
cache_config.dasqt_common_mode_removal = p.dasqt_common_mode_removal;
cache_config.raw_channel_first0 = p.raw_channel_first0;
cache_config.n_station = p.n_station;
cache_config.reference_gather = p.ccf_reference_gather;
cache_config.reference_channel = p.reference_channel;
cache_config.include_reference_autocorrelation = ...
    p.include_reference_autocorrelation;

cache_config.keep_pattern = keep(ids,:);

ok = false;

if isfile(cache_file)
    old = load(cache_file,'cache_config');
    if isfield(old,'cache_config') && ...
            isequaln(old.cache_config,cache_config)
        ok = true;
        return;
    end
end

ccf_sum = [];
count_sum = [];
ccr = [];
info = [];
freq = [];

% 逐600 s缓存段计算参考道到全部接收道的互相关，并按有效窗数线性叠加。
for ii = 1:numel(ids)

    ih = ids(ii);

    active = logical(keep(ih,:));
    if nnz(active)<2
        continue;
    end

    A = load(file_paths(ih),'wave');
    wave = double(A.wave);
    assert(isequal(size(wave),[p.segment_samples,numel(p.station_x)]), ...
        'DASQt cache segment尺寸与CCF阵列不一致：%s',file_paths(ih));
    % DASQt已经完成去均值、去趋势、taper和带通；此处只应用EDWav mask。
    wave(:,~active) = 0;

    if p.ccf_reference_gather
        rr = make_reference_rr(p.station_x,p.reference_channel, ...
            p.include_reference_autocorrelation);
    else
        rr = [];
    end

    C = mCCFJ.correlate( ...
        wave, ...
        [p.station_x;zeros(size(p.station_x))], ...
        p.Fs, ...
        'AX','xyz', ...
        'CL',p.segment_samples, ...
        'OL',0, ...
        'FL',p.ccf_fft_length, ...
        'NT',p.ccf_time_normalization, ...
        'NF',p.ccf_frequency_normalization, ...
        'FM',p.ccf_maximum_frequency, ...
        'FD',p.ccf_frequency_decimation, ...
        'TP',p.ccf_taper, ...
        'RR',rr, ...
        'GPU','No');

    frequency_id = C.freq<=p.ccf_maximum_frequency;
    count = double(C.info.cstack(:).');

    if isempty(ccf_sum)

        ccf_sum = zeros(sum(frequency_id), ...
            size(C.ccf,2),'like',C.ccf);

        count_sum = zeros(size(count));

        freq = C.freq(frequency_id);
        ccr = C.ccr;
        info = C.info;
    end

    ccf_sum = ccf_sum + ...
        C.ccf(frequency_id,:).*count;

    count_sum = count_sum + count;
    fprintf('MATLAB PSD CCF segment %d/%d: kept channels=%d, valid pairs=%d\n', ...
        ii,numel(ids),nnz(active),nnz(count>0));
end

if isempty(count_sum) || ~any(count_sum>0)
    return;
end

ccf = zeros(size(ccf_sum),'like',ccf_sum);

valid_pair = count_sum>0;

ccf(:,valid_pair) = ...
    ccf_sum(:,valid_pair)./count_sum(valid_pair);

info.cstack = count_sum;

save(cache_file, ...
    'ccf','freq','ccr','info','count_sum', ...
    'cache_config','-v7.3');

ok = true;
end

%% 从一个未mute的24 h CCF计算F-J频散谱
function [FJ,spectrum,offset,ridge_velocity,pair_count_day] = ...
    compute_fj_from_ccf(cache_file,p)

FJ = [];
spectrum = [];
offset = [];
ridge_velocity = [];
pair_count_day = 0;

S = load(cache_file,'ccf','freq','ccr','info','count_sum');

df = median(diff(S.freq));

CC.freq = (0:df:p.Fs/2).';
CC.ccf = zeros(numel(CC.freq),size(S.ccf,2),'like',S.ccf);
CC.ccf(1:size(S.ccf,1),:) = S.ccf;

CC.ccr = S.ccr;
CC.info = S.info;

CC.cct = fftshift(ifft( ...
    [CC.ccf;conj(CC.ccf(end-1:-1:2,:))], ...
    [],1,'symmetric'),1);

CC.time = ((1:size(CC.cct,1)) - ...
    (floor(size(CC.cct,1)/2)+1))./p.Fs;

pair_count_day = sum(S.count_sum);

%% 距离分箱、filtering和双边GW mute
CC = mCCFJ.stack_bin(CC,p.distance_bin_m);

if iscell(CC.ccr)
    offset = cell2mat(CC.ccr(:,1));
else
    offset = CC.ccr(:,1);
end

offset = offset(:);

if numel(unique(offset))<2
    FJ = [];
    spectrum = [];
    ridge_velocity = [];
    return;
end

CC.ccf(~isfinite(CC.ccf)) = 0;

% 0 m自相关保留在500道记录中，但不进入按offset设计的速度滤波。
CC = remove_zero_offset_columns(CC);
offset = offset_from_ccr(CC.ccr);
CC = mCCFJ.filtering(CC,p.filter_velocity);

dt = median(diff(CC.time));

positive = find(CC.time>=0);
negative = find(CC.time<=0);
negative = negative(2:end);

data = 0.5*( ...
    CC.cct(positive,:) + ...
    flipud(CC.cct(negative,:)));

if p.apply_gw_mute
    reference_n = round(p.mute_reference_s/dt);
    r = offset.';
    T1 = round(reference_n/p.top_mute(3));
    T0 = round(p.top_mute(2)/dt);
    data = GW_mute(data,T1,r,zeros(size(r)),T0, ...
        p.top_mute(1),dt,0);
    T1 = round(reference_n/p.bottom_mute(3));
    T0 = round(p.bottom_mute(2)/dt);
    data = GW_mute1(data,T1,r,zeros(size(r)),T0, ...
        p.bottom_mute(1),dt,0);
end

%% 恢复对称互相关
CC.cct = [ ...
    zeros(1,size(data,2),'like',data); ...
    flipud(data(2:end,:)); ...
    data];

CC.ccf = fft(ifftshift(CC.cct,1));
CC.ccf = CC.ccf(1:numel(CC.freq),:);

%% 按目标frequency_step抽取F-J输入频率
df = median(diff(CC.freq));

stride = max(1,round(p.frequency_step/df));

frequency_id = find(CC.freq<=p.frequency_range(2));
frequency_id = frequency_id(1:stride:end);

CC.ccf = CC.ccf(frequency_id,:);
CC.freq = CC.freq(frequency_id);

%% mCCFJ频散成像
FJ = mCCFJ.transform( ...
    CC, ...
    p.velocity, ...
    p.frequency_range, ...
    'Fun',p.fj_function, ...
    'Win',p.fj_window, ...
    'GPU','No', ...
    'Num',0);

% 保留mCCFJ.transform的原始F-J幅值。
% 不做逐频率归一化，综合底图和单日检查图都使用这个原始幅值。
spectrum = abs(real(FJ.dsp));

%% 原版findpeaks + 趋势追踪ridge
valid_velocity = ...
    p.velocity>=p.pick_velocity_range(1) & ...
    p.velocity<=p.pick_velocity_range(2);

pick_spectrum = spectrum;
pick_spectrum(~valid_velocity,:) = 0;

[~,seed] = min(abs(FJ.frq-p.pick_seed_frequency));

first_velocity = find(valid_velocity,1,'first');
last_velocity = find(valid_velocity,1,'last');

ridge = pickRidgeAlongTrend( ...
    pick_spectrum,seed,first_velocity,last_velocity);

ridge_velocity = p.velocity(ridge);
end

%% 将单日F-J频散谱插值到统一frequency轴
function [spectrum_day,ridge_day,pair_count_day] = ...
    dispersion_from_ccf(cache_file,p)

spectrum_day = [];
ridge_day = nan(size(p.frequency));
pair_count_day = 0;

[FJ,spectrum,~,ridge_velocity,pair_count_day] = ...
    compute_fj_from_ccf(cache_file,p);

if isempty(FJ) || isempty(spectrum)
    return;
end

spectrum_day = interp1( ...
    FJ.frq(:),spectrum.',p.frequency(:), ...
    'linear',nan).';

% The transform may represent an exact 1 Hz endpoint as 1+roundoff.
% Snap only targets outside the source range by less than one millionth
% of a frequency step; do not extrapolate a genuinely missing band.
frequency_tolerance = max(100*eps(max(abs(FJ.frq))), ...
    p.frequency_step*1e-6);
below_first = p.frequency(:)<FJ.frq(1) & ...
    FJ.frq(1)-p.frequency(:)<=frequency_tolerance;
above_last = p.frequency(:)>FJ.frq(end) & ...
    p.frequency(:)-FJ.frq(end)<=frequency_tolerance;
if any(below_first)
    spectrum_day(:,below_first) = repmat(spectrum(:,1),1,nnz(below_first));
end
if any(above_last)
    spectrum_day(:,above_last) = repmat(spectrum(:,end),1,nnz(above_last));
end

ridge_day = interp1( ...
    FJ.frq(:),ridge_velocity(:),p.frequency(:), ...
    'linear',nan);
if any(below_first)
    ridge_day(below_first) = ridge_velocity(1);
end
if any(above_last)
    ridge_day(above_last) = ridge_velocity(end);
end
end

%% 使用完整综合人工mask，并根据当天ridge自动微调后提取衰减
function [alpha_day,mask_point_count,ok] = ...
    attenuation_from_manual_mask( ...
        cache_file,p,composite_mask_low_velocity, ...
        composite_mask_high_velocity,composite_ridge_velocity)

alpha_day = nan(size(p.frequency));
mask_point_count = 0;
ok = false;

[FJ,~,offset,daily_ridge_velocity,~] = ...
    compute_fj_from_ccf(cache_file,p);

if isempty(FJ)
    return;
end

%% 将综合mask和综合ridge插值到当天FJ频率
composite_low_fj = interp1( ...
    p.frequency(:),composite_mask_low_velocity(:),FJ.frq(:), ...
    'linear','extrap');

composite_high_fj = interp1( ...
    p.frequency(:),composite_mask_high_velocity(:),FJ.frq(:), ...
    'linear','extrap');

composite_ridge_fj = interp1( ...
    p.frequency(:),composite_ridge_velocity(:),FJ.frq(:), ...
    'linear','extrap');

%% 当天ridge相对于综合ridge的速度偏移
delta_velocity = ...
    daily_ridge_velocity(:)-composite_ridge_fj(:);

delta_velocity(~isfinite(delta_velocity)) = 0;

%% 当天mask上下边界
daily_low = composite_low_fj + delta_velocity;
daily_high = composite_high_fj + delta_velocity;

% 防止超出velocity计算范围
daily_low = max(daily_low,min(p.velocity));
daily_high = min(daily_high,max(p.velocity));

%% 建立当天二值mask
mask = false(numel(p.velocity),numel(FJ.frq));

for jf = 1:numel(FJ.frq)

    mask(:,jf) = ...
        p.velocity>=daily_low(jf) & ...
        p.velocity<=daily_high(jf);
end

mask_point_count = nnz(mask);

if mask_point_count==0
    return;
end

%% F-J反变换
FJ.dsp = real(FJ.dsp);

Cinv = mCCFJ.inversion( ...
    FJ, ...
    offset, ...
    double(mask), ...
    'Threshold',p.fj_inverse_threshold, ...
    'Plt','real', ...
    'GPU','No', ...
    'Num',0, ...
    'ShowMask','No');

distance_id = ...
    Cinv.ccr(:,1)>=p.offset_range(1) & ...
    Cinv.ccr(:,1)<=p.offset_range(2);

fit_frequency_id = ...
    Cinv.freq>=p.frequency_range(1) & ...
    Cinv.freq<=p.frequency_range(2);

wmax = max(abs(real( ...
    Cinv.ccf(fit_frequency_id,distance_id))), ...
    [],'all');

if ~isfinite(wmax) || wmax<=0
    return;
end

w_grid = linspace(0,1.2*wmax,101);

[attenuation,~,fa] = mCCFJ.attenuation( ...
    Cinv, ...
    p.frequency_range, ...
    p.offset_range, ...
    p.alpha_grid, ...
    w_grid, ...
    'kind',p.attenuation_function, ...
    'envelope',p.attenuation_envelope, ...
    'ShowResults','No');

alpha_day = interp1( ...
    fa,attenuation,p.frequency, ...
    'linear',nan);

ok = any(isfinite(alpha_day));
end

%% 在综合频散谱上手动拾取闭合polygon
function [polygon_frequency,polygon_velocity, ...
    mask_low_velocity,mask_high_velocity,mask,fig] = ...
    pickManualPolygonMask( ...
        frequency,velocity,spectrum,composite_ridge_velocity)

polygon_frequency = [];
polygon_velocity = [];

fig = figure( ...
    'Color','w', ...
    'Position',[120 80 1050 700], ...
    'Name','Manual F-J mask picking', ...
    'NumberTitle','off');

ax = axes(fig);

imagesc(ax,frequency,velocity,spectrum);
axis(ax,'xy');
colormap(ax,jet);
colorbar(ax);

% 这里只调整显示色标，不修改spectrum数据本身。
finite_spectrum = spectrum(isfinite(spectrum));
if ~isempty(finite_spectrum)
    spectrum_limit = prctile(finite_spectrum,99.5);
    if isfinite(spectrum_limit) && spectrum_limit>0
        caxis(ax,[0 spectrum_limit]);
    end
end

hold(ax,'on');

plot(ax,frequency,composite_ridge_velocity, ...
    'k-','LineWidth',1.3);

h_line = plot(ax,nan,nan, ...
    'w-','LineWidth',1.5);

h_point = plot(ax,nan,nan, ...
    'wo', ...
    'MarkerFaceColor','w', ...
    'MarkerSize',5);

xlim(ax,[frequency(1) frequency(end)]);
ylim(ax,[velocity(1) min(600,velocity(end))]);

xlabel(ax,'Frequency (Hz)');
ylabel(ax,'Phase velocity (m/s)');

title(ax,{ ...
    'Manual mask on composite F-J spectrum', ...
    '左键增加顶点；右键撤回；回车闭合'}, ...
    'FontWeight','normal');

fprintf('请在弹出的综合频散谱上拾取polygon mask。\n');
fprintf('不需要精确点到frequency range左右端点，程序会自动沿综合ridge补齐。\n');

while true

    figure(fig);
    axes(ax); %#ok<LAXES>

    [x,y,button] = ginput(1);

    % ginput(1)中按回车通常返回空数组。
    % 已有至少3个顶点时，空返回即表示完成并闭合。
    if isempty(button)

        if numel(polygon_frequency)>=3
            break;
        else
            title(ax,{ ...
                '至少需要3个顶点才能闭合polygon', ...
                '左键增加顶点；右键撤回；回车闭合'}, ...
                'FontWeight','normal');
            drawnow;
            continue;
        end
    end

    if button==1

        xl = xlim(ax);
        yl = ylim(ax);

        if x>=xl(1) && x<=xl(2) && y>=yl(1) && y<=yl(2)

            polygon_frequency(end+1,1) = x; %#ok<AGROW>
            polygon_velocity(end+1,1) = y; %#ok<AGROW>
        end

    elseif button==3

        if ~isempty(polygon_frequency)

            polygon_frequency(end) = [];
            polygon_velocity(end) = [];
        end

    elseif button==13 || button==10

        if numel(polygon_frequency)>=3
            break;
        else
            title(ax,{ ...
                '至少需要3个顶点才能闭合polygon', ...
                '左键增加顶点；右键撤回；回车闭合'}, ...
                'FontWeight','normal');
        end
    end

    set(h_line, ...
        'XData',polygon_frequency, ...
        'YData',polygon_velocity);

    set(h_point, ...
        'XData',polygon_frequency, ...
        'YData',polygon_velocity);

    drawnow;
end

%% 闭合原始人工polygon
polygon_frequency(end+1,1) = polygon_frequency(1);
polygon_velocity(end+1,1) = polygon_velocity(1);

%% 先把原始polygon投影到frequency网格上
[frequency_grid,velocity_grid] = meshgrid(frequency,velocity);

raw_mask = inpolygon( ...
    frequency_grid,velocity_grid, ...
    polygon_frequency,polygon_velocity);

mask_low_velocity = nan(numel(frequency),1);
mask_high_velocity = nan(numel(frequency),1);

for jf = 1:numel(frequency)

    id = find(raw_mask(:,jf));

    if ~isempty(id)

        mask_low_velocity(jf) = velocity(id(1));
        mask_high_velocity(jf) = velocity(id(end));
    end
end

valid_column = ...
    isfinite(mask_low_velocity) & ...
    isfinite(mask_high_velocity);

if ~any(valid_column)
    error('人工polygon没有覆盖任何frequency网格点，请重新拾取。');
end

%% 填补人工polygon覆盖区内部可能出现的离散空列
valid_id = find(valid_column);
first_id = valid_id(1);
last_id = valid_id(end);

inside = (first_id:last_id).';

if numel(valid_id)>=2

    mask_low_velocity(inside) = interp1( ...
        frequency(valid_id),mask_low_velocity(valid_id), ...
        frequency(inside),'linear');

    mask_high_velocity(inside) = interp1( ...
        frequency(valid_id),mask_high_velocity(valid_id), ...
        frequency(inside),'linear');
end

%% 左侧自动补齐到frequency_range起点
% 保持人工polygon最左端上下边界相对composite ridge的偏移量。
if first_id>1

    lower_offset = ...
        mask_low_velocity(first_id)-composite_ridge_velocity(first_id);

    upper_offset = ...
        mask_high_velocity(first_id)-composite_ridge_velocity(first_id);

    mask_low_velocity(1:first_id-1) = ...
        composite_ridge_velocity(1:first_id-1)+lower_offset;

    mask_high_velocity(1:first_id-1) = ...
        composite_ridge_velocity(1:first_id-1)+upper_offset;
end

%% 右侧自动补齐到frequency_range终点
% 保持人工polygon最右端上下边界相对composite ridge的偏移量。
if last_id<numel(frequency)

    lower_offset = ...
        mask_low_velocity(last_id)-composite_ridge_velocity(last_id);

    upper_offset = ...
        mask_high_velocity(last_id)-composite_ridge_velocity(last_id);

    mask_low_velocity(last_id+1:end) = ...
        composite_ridge_velocity(last_id+1:end)+lower_offset;

    mask_high_velocity(last_id+1:end) = ...
        composite_ridge_velocity(last_id+1:end)+upper_offset;
end

%% 限制到velocity计算范围
mask_low_velocity = ...
    max(mask_low_velocity,min(velocity));

mask_high_velocity = ...
    min(mask_high_velocity,max(velocity));

%% 建立最终完整综合mask
mask = false(numel(velocity),numel(frequency));

for jf = 1:numel(frequency)

    mask(:,jf) = ...
        velocity>=mask_low_velocity(jf) & ...
        velocity<=mask_high_velocity(jf);
end

%% 清晰显示最终完整mask
% 原始人工顶点
set(h_point, ...
    'XData',polygon_frequency(1:end-1), ...
    'YData',polygon_velocity(1:end-1));

% 不再突出原始闭合边，仅显示完整最终边界
set(h_line,'XData',nan,'YData',nan);

% 完整mask半透明填充：包括程序自动补齐的左右两端
fill_frequency = [frequency;flipud(frequency)];
fill_velocity = [mask_low_velocity;flipud(mask_high_velocity)];

patch(ax, ...
    fill_frequency,fill_velocity,'w', ...
    'FaceAlpha',0.20, ...
    'EdgeColor','none');

plot(ax,frequency,mask_low_velocity, ...
    'w-','LineWidth',2.0);

plot(ax,frequency,mask_high_velocity, ...
    'w-','LineWidth',2.0);

% 人工原始polygon用虚线显示，方便区分“人工部分”和“自动补齐部分”
plot(ax,polygon_frequency,polygon_velocity, ...
    'w--','LineWidth',1.0);

% 综合ridge重新画在最上层
plot(ax,frequency,composite_ridge_velocity, ...
    'k-','LineWidth',1.3);

title(ax,{ ...
    'Composite F-J spectrum with completed manual mask', ...
    '白实线/半透明区域 = 最终完整mask；白虚线 = 原始人工polygon'}, ...
    'FontWeight','normal');

drawnow;
end

%% 显示已有综合mask
function fig = showCompositeMask( ...
    frequency,velocity,spectrum,composite_ridge_velocity, ...
    polygon_frequency,polygon_velocity, ...
    mask_low_velocity,mask_high_velocity)

fig = figure( ...
    'Color','w', ...
    'Position',[120 80 1050 700], ...
    'Name','Composite F-J spectrum and saved mask', ...
    'NumberTitle','off');

ax = axes(fig);

imagesc(ax,frequency,velocity,spectrum);
axis(ax,'xy');
colormap(ax,jet);
colorbar(ax);

finite_spectrum = spectrum(isfinite(spectrum));
if ~isempty(finite_spectrum)
    spectrum_limit = prctile(finite_spectrum,99.5);
    if isfinite(spectrum_limit) && spectrum_limit>0
        caxis(ax,[0 spectrum_limit]);
    end
end

hold(ax,'on');

fill_frequency = [frequency;flipud(frequency)];
fill_velocity = [mask_low_velocity;flipud(mask_high_velocity)];

patch(ax, ...
    fill_frequency,fill_velocity,'w', ...
    'FaceAlpha',0.20, ...
    'EdgeColor','none');

plot(ax,frequency,mask_low_velocity, ...
    'w-','LineWidth',2.0);

plot(ax,frequency,mask_high_velocity, ...
    'w-','LineWidth',2.0);

plot(ax,polygon_frequency,polygon_velocity, ...
    'w--','LineWidth',1.0);

plot(ax,frequency,composite_ridge_velocity, ...
    'k-','LineWidth',1.3);

xlim(ax,[frequency(1) frequency(end)]);
ylim(ax,[velocity(1) min(600,velocity(end))]);

xlabel(ax,'Frequency (Hz)');
ylabel(ax,'Phase velocity (m/s)');

title(ax,{ ...
    'Composite raw F-J spectrum with saved manual mask', ...
    '白实线/半透明区域 = 完整mask；白虚线 = 原始人工polygon'}, ...
    'FontWeight','normal');
end

%% 沿趋势拾取频散ridge
function ridge = pickRidgeAlongTrend( ...
    spectrum,seed,first_velocity,last_velocity)

% 从种子频率向两侧逐列追踪局部峰值；
% 不做低频拉平和插值。

n_frequency = size(spectrum,2);

ridge = nan(n_frequency,1);

[~,seed_local] = ...
    max(spectrum(first_velocity:last_velocity,seed));

ridge(seed) = ...
    first_velocity+seed_local-1;

if seed>1

    ridge(seed-1) = chooseTrendPeak( ...
        spectrum(:,seed-1), ...
        ridge(seed), ...
        nan, ...
        first_velocity,last_velocity);
end

for jf = seed-2:-1:1

    ridge(jf) = chooseTrendPeak( ...
        spectrum(:,jf), ...
        ridge(jf+1), ...
        ridge(jf+2), ...
        first_velocity,last_velocity);
end

if seed<n_frequency

    ridge(seed+1) = chooseTrendPeak( ...
        spectrum(:,seed+1), ...
        ridge(seed), ...
        nan, ...
        first_velocity,last_velocity);
end

for jf = seed+2:n_frequency

    ridge(jf) = chooseTrendPeak( ...
        spectrum(:,jf), ...
        ridge(jf-1), ...
        ridge(jf-2), ...
        first_velocity,last_velocity);
end
end

%% 选择最符合前一频率趋势的局部峰值
function index = chooseTrendPeak( ...
    column,previous,previous_previous, ...
    first_velocity,last_velocity)

column = double(column(:));
column(~isfinite(column)) = 0;

[~,candidate] = findpeaks(column);

candidate = candidate( ...
    candidate>=first_velocity & ...
    candidate<=last_velocity);

if isempty(candidate)

    [~,local_index] = ...
        max(column(first_velocity:last_velocity));

    index = ...
        first_velocity+local_index-1;

    return;
end

if isfinite(previous_previous)
    expected = 2*previous-previous_previous;
else
    expected = previous;
end

distance = abs(candidate-expected);

nearest = candidate( ...
    distance==min(distance));

[~,best] = ...
    max(column(nearest));

index = nearest(best);
end

%% 调用Python DASQt预处理并复用可验证的MAT缓存
function ensure_dasqt_cache(raw_dir,cache_dir,python_bin,python_script, ...
    channel_first0,channel_count,Fs,dasqt_source,spacing,gauge,segment_seconds,max_segments,band, ...
    butter_order,tukey_alpha,common_mode,rebuild_cache)

assert(isfile(python_script),'DASQt预处理脚本不存在：%s',python_script);
assert(isfile(python_bin),'Python解释器不存在：%s',python_bin);

overwrite = '';
if rebuild_cache, overwrite = ' --overwrite'; end

cmd = sprintf(['%s %s --data-dir %s --output-dir %s ' ...
    '--channel-first %d --channel-count %d --fs-hz %.12g ' ...
    '--dasqt-source %s --channel-spacing-m %.12g --gauge-length-m %.12g ' ...
    '--segment-seconds %d --max-segments %d ' ...
    '--band %.12g %.12g --butter-order %d --tukey-alpha %.12g%s'], ...
    shell_quote(python_bin),shell_quote(python_script), ...
    shell_quote(raw_dir),shell_quote(cache_dir),channel_first0,channel_count, ...
    Fs,shell_quote(dasqt_source),spacing,gauge,segment_seconds,max_segments, ...
    band(1),band(2),butter_order,tukey_alpha,overwrite);
if ~common_mode
    cmd = [cmd ' --no-common-mode-removal']; %#ok<AGROW>
end

[status,message] = system(cmd);
assert(status==0,'DASQt预处理失败：\n%s',message);
end

%% 将NyHt/杨博MATLAB版EDWav加入路径
function load_edwav_class_local(edwav_dir)
assert(isfile(fullfile(edwav_dir,'EDWav.m')), ...
    'MATLAB版EDWav.m不存在：%s',edwav_dir);
addpath(edwav_dir,'-begin');
end

%% 保存EDWav逐600 s、逐道筛选表
function write_edwav_csv(path,segment_start,proxy,raw_valid,eligible,keep)
fid = fopen(path,'w');
assert(fid>0,'无法写入EDWav CSV：%s',path);
fprintf(fid,'segment_start,local_channel,proxy,raw_valid,eligible,keep\n');
for iseg = 1:size(proxy,1)
    for ich = 1:size(proxy,2)
        fprintf(fid,'%s,%d,%.12g,%d,%d,%d\n', ...
            char(segment_start(iseg)),ich-1,proxy(iseg,ich), ...
            raw_valid(iseg,ich),eligible(iseg,ich),keep(iseg,ich));
    end
end
fclose(fid);
end

%% 绘制全500道24 h CCF offset gather
function plot_ccf_gather_24h(cache_file,p,out_dir)
S = load(cache_file,'ccf','freq','ccr','info');
df = median(diff(S.freq));

CC.freq = (0:df:p.Fs/2).';
CC.ccf = zeros(numel(CC.freq),size(S.ccf,2),'like',S.ccf);
CC.ccf(1:size(S.ccf,1),:) = S.ccf;
CC.ccr = S.ccr;
CC.info = S.info;
CC.cct = fftshift(ifft( ...
    [CC.ccf;conj(CC.ccf(end-1:-1:2,:))], ...
    [],1,'symmetric'),1);
CC.time = ((1:size(CC.cct,1)) - ...
    (floor(size(CC.cct,1)/2)+1))./p.Fs;

CC = mCCFJ.stack_bin(CC,p.distance_bin_m);
if iscell(CC.ccr)
    offset_all = cell2mat(CC.ccr(:,1));
else
    offset_all = CC.ccr(:,1);
end
offset_all = offset_all(:);
CC.ccf(~isfinite(CC.ccf)) = 0;
% mCCFJ.filtering不能处理0 m自相关；先对499个非零offset滤波，
% 再把未滤波的0 m自相关放回500道gather。
CCfilt = remove_zero_offset_columns(CC);
CCfilt = mCCFJ.filtering(CCfilt,p.filter_velocity);
offset = offset_from_ccr(CCfilt.ccr);

positive = find(CCfilt.time>=0);
negative = find(CCfilt.time<=0);
negative = negative(2:end);
data_nonzero = 0.5*(CCfilt.cct(positive,:) + flipud(CCfilt.cct(negative,:)));
time_positive = CCfilt.time(positive);

dt = median(diff(CCfilt.time));
reference_n = round(p.mute_reference_s/dt);
r = offset.';
T1 = round(reference_n/p.top_mute(3));
T0 = round(p.top_mute(2)/dt);
data_nonzero = GW_mute(data_nonzero,T1,r,zeros(size(r)),T0, ...
    p.top_mute(1),dt,0);
T1 = round(reference_n/p.bottom_mute(3));
T0 = round(p.bottom_mute(2)/dt);
data_nonzero = GW_mute1(data_nonzero,T1,r,zeros(size(r)),T0, ...
    p.bottom_mute(1),dt,0);

% 恢复0 m自相关列，使输出仍为500条记录；该列不用于F-J。
offset_all = offset_from_ccr(CC.ccr);
keep_nonzero = abs(offset_all)>eps;
zero_col = find(~keep_nonzero,1,'first');
data = zeros(numel(time_positive),numel(offset_all),'like',data_nonzero);
data(:,keep_nonzero) = data_nonzero;
if ~isempty(zero_col)
    raw_zero = 0.5*(CC.cct(positive,zero_col) + ...
        flipud(CC.cct(negative,zero_col)));
    data(:,zero_col) = raw_zero;
end

show_id = time_positive>=0 & time_positive<=10;
if ~any(show_id), show_id = true(size(time_positive)); end
raw_show_nonzero = 0.5*(CCfilt.cct(positive(show_id),:) + ...
    flipud(CCfilt.cct(negative(show_id),:)));
raw_show = zeros(size(data(show_id,:)),'like',data);
raw_show(:,keep_nonzero) = raw_show_nonzero;
if ~isempty(zero_col)
    raw_show(:,zero_col) = 0.5*(CC.cct(positive(show_id),zero_col) + ...
        flipud(CC.cct(negative(show_id),zero_col)));
end
muted_show = data(show_id,:);
raw_clip = prctile(abs(raw_show(:)),99);
muted_clip = prctile(abs(muted_show(:)),99);
clip = max([raw_clip,muted_clip,eps]);

fig = figure('Color','w','Position',[60 60 1450 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
ax = nexttile;
imagesc(ax,offset_all,time_positive(show_id),raw_show);
axis(ax,'xy'); caxis(ax,[-clip clip]); colormap(ax,redblue_map_local());
colorbar(ax); xlabel(ax,'Offset (m)'); ylabel(ax,'Lag (s)');
title(ax,'500-trace reference-gather, 24 h PSD-mCCFJ CCF before GW mute');
ax = nexttile;
imagesc(ax,offset_all,time_positive(show_id),muted_show);
axis(ax,'xy'); caxis(ax,[-clip clip]); colormap(ax,redblue_map_local());
colorbar(ax); xlabel(ax,'Offset (m)'); ylabel(ax,'Lag (s)');
title(ax,'500-trace reference-gather after filtering and two-sided GW mute');
exportgraphics(fig,fullfile(out_dir,'ccf_24h_500ch_offset_gather.png'), ...
    'Resolution',250);
end

function cmap = redblue_map_local()
n = 256;
left = [linspace(0,1,n/2).' linspace(0,1,n/2).' ones(n/2,1)];
right = [ones(n/2,1) linspace(1,0,n/2).' linspace(1,0,n/2).'];
cmap = [left;right];
end

function plot_default_preview(cache_file,p, ...
    frequency,velocity,spectrum,ridge_velocity,out_dir)
%PLOT_DEFAULT_PREVIEW Write the default no-mute CCF/F-J three-panel figure.
S = load(cache_file,'ccf','freq','ccr','info','count_sum');
df = median(diff(S.freq));
CC.freq = (0:df:p.Fs/2).';
CC.ccf = zeros(numel(CC.freq),size(S.ccf,2),'like',S.ccf);
CC.ccf(1:size(S.ccf,1),:) = S.ccf;
CC.ccr = S.ccr;
CC.info = S.info;
CC.cct = fftshift(ifft([CC.ccf;conj(CC.ccf(end-1:-1:2,:))],[],1,'symmetric'),1);
CC.time = ((1:size(CC.cct,1))-(floor(size(CC.cct,1)/2)+1))./p.Fs;
CC = mCCFJ.stack_bin(CC,p.distance_bin_m);
CC.ccf(~isfinite(CC.ccf)) = 0;
CC_nonzero = remove_zero_offset_columns(CC);
CC_nonzero = mCCFJ.filtering(CC_nonzero,p.filter_velocity);
positive = find(CC_nonzero.time>=0);
negative = find(CC_nonzero.time<=0); negative = negative(2:end);
positive = positive(:);
negative = negative(:);
ccf_positive = 0.5*(CC_nonzero.cct(positive,:) + flipud(CC_nonzero.cct(negative,:)));
time_positive = CC_nonzero.time(positive);
time_positive = time_positive(:);
offset_all = offset_from_ccr(CC.ccr);
keep_nonzero = abs(offset_all)>eps;
zero_col = find(~keep_nonzero,1,'first');
ccf_gather = zeros(numel(time_positive),numel(offset_all),'like',ccf_positive);
ccf_gather(:,keep_nonzero) = ccf_positive;
if ~isempty(zero_col)
    ccf_gather(:,zero_col) = 0.5*(CC.cct(positive,zero_col)+flipud(CC.cct(negative,zero_col)));
end
time_window = [-flipud(time_positive(2:end));time_positive];
ccf_two_sided = [flipud(ccf_gather(2:end,:));ccf_gather];
[raw_show,time_window] = crop_ccf_window( ...
    ccf_two_sided,time_window,p.ccf_window_half_s);
raw_clip = prctile(abs(raw_show(:)),99);
if ~isfinite(raw_clip) || raw_clip<=0, raw_clip = 1; end
trace_rms = sqrt(mean(raw_show.^2,1));
trace_rms(~isfinite(trace_rms) | trace_rms<=0) = 1;
normalized_show = raw_show./trace_rms;
normalized_clip = prctile(abs(normalized_show(:)),99);
if ~isfinite(normalized_clip) || normalized_clip<=0, normalized_clip = 1; end
finite_spec = spectrum(isfinite(spectrum));
spec_clip = prctile(finite_spec,99.5);
if ~isfinite(spec_clip) || spec_clip<=0, spec_clip = 1; end

fig = figure('Color','w','Position',[60 40 1450 1220]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
ax = nexttile; imagesc(ax,offset_all,time_window,raw_show);
set(ax,'YDir','reverse'); caxis(ax,[-raw_clip raw_clip]);
colormap(ax,redblue_map_local()); colorbar(ax);
xlabel(ax,'Offset from reference channel (m)'); ylabel(ax,'Time (s)');
if p.n_station==500 && p.ccf_window_half_s==1 && ~p.apply_gw_mute
    title(ax,'500-channel PSD-mCCFJ CCF, no GW mute (±1 s window)');
else
    title(ax,sprintf('%d-channel PSD-mCCFJ CCF, no GW mute (±%.3g s window)', ...
        p.n_station,p.ccf_window_half_s));
end
ax = nexttile; imagesc(ax,offset_all,time_window,normalized_show);
set(ax,'YDir','reverse'); caxis(ax,[-normalized_clip normalized_clip]);
colormap(ax,redblue_map_local()); colorbar(ax);
xlabel(ax,'Offset from reference channel (m)'); ylabel(ax,'Time (s)');
if p.n_station==500 && p.ccf_window_half_s==1 && ~p.apply_gw_mute
    title(ax,'Same CCF, trace-normalized only for display QC (all 500 offsets)');
else
    title(ax,sprintf('Same CCF, trace-normalized only for display QC (%d offsets)', ...
        p.n_station));
end
ax = nexttile; imagesc(ax,frequency,velocity,spectrum); axis(ax,'xy');
caxis(ax,[0 spec_clip]); colormap(ax,jet); colorbar(ax); hold(ax,'on');
plot(ax,frequency,ridge_velocity,'k-','LineWidth',1.4);
xline(ax,p.fj_reliable_range(2),'w--','LineWidth',1.4);
xlim(ax,p.frequency_range); ylim(ax,[velocity(1) min(800,velocity(end))]);
xlabel(ax,'Frequency (Hz)'); ylabel(ax,'Phase velocity (m/s)');
if p.n_station==500 && isequal(p.frequency_range,[1 15]) && ...
        p.ccf_window_half_s==1 && ~p.apply_gw_mute
    title(ax,'H2 F-J spectrum, 1--15 Hz (DASQt preprocessing band starts at 3 Hz)');
else
    title(ax,sprintf('H2 F-J spectrum, %.3g--%.3g Hz (preprocessing band %.3g--%.3g Hz)', ...
        p.frequency_range(1),p.frequency_range(2),p.dasqt_band(1),p.dasqt_band(2)));
end
png_file = fullfile(out_dir,sprintf('mccfj_composite_%dch.png',p.n_station));
preview_file = fullfile(out_dir,sprintf('ccf_preview_%dch.mat',p.n_station));
if p.n_station==500 && isequal(p.frequency_range,[1 15]) && ...
        p.ccf_window_half_s==1 && ~p.apply_gw_mute
    png_file = fullfile(out_dir,'mccfj_composite_500ch_24h.png');
    preview_file = fullfile(out_dir,'ccf_24h_500ch_no_mute_pm1s_fj_1_15.mat');
end
exportgraphics(fig,png_file,'Resolution',300);
if p.n_station==500 && isequal(p.frequency_range,[1 15]) && ...
        p.ccf_window_half_s==1 && ~p.apply_gw_mute
    copyfile(png_file,fullfile(out_dir, ...
        'ccf_24h_500ch_no_mute_pm1s_fj_1_15_qc.png'));
end
count_sum = S.count_sum;
ccf_gather = raw_show;
ccf_time_s = time_window;
save(preview_file,'ccf_gather','ccf_time_s','offset_all','spectrum', ...
    'ridge_velocity','frequency','velocity','p','count_sum','cache_file','-v7.3');
end

function CC = remove_zero_offset_columns(CC)
% mCCFJ速度滤波要求offset>0；保留非零offset列供F-J和mute使用。
offset = offset_from_ccr(CC.ccr);
keep = abs(offset(:))>eps;
CC.ccf = CC.ccf(:,keep);
CC.ccr = CC.ccr(keep,:);
if isfield(CC,'cct')
    CC.cct = CC.cct(:,keep);
end
end

function offset = offset_from_ccr(ccr)
if iscell(ccr)
    offset = cell2mat(ccr(:,1));
else
    offset = ccr(:,1);
end
offset = offset(:);
end

%% 构造mCCFJ参考道到全部500道的单炮式RR
function RR = make_reference_rr(station_x,reference_channel,include_self)
n_station = numel(station_x);
receiver_id = 1:n_station;
if ~include_self
    receiver_id(receiver_id==reference_channel) = [];
end

RR = cell(numel(receiver_id),6);
for ii = 1:numel(receiver_id)
    jj = receiver_id(ii);
    RR{ii,1} = abs(station_x(jj)-station_x(reference_channel));
    RR{ii,2} = reference_channel;
    RR{ii,3} = jj;
    RR{ii,4} = 0;
    RR{ii,5} = reference_channel;
    RR{ii,6} = jj;
end
end
