function export_demo()
%EXPORT_DEMO Package the real San Jose preview without machine-specific paths.
root = fileparts(fileparts(mfilename('fullpath')));
source_dir = fullfile(root,'outputs','demo_sanjose_small');
target_dir = fullfile(root,'docs','demo');
cache_target = fullfile(root,'data','demo_sanjose_50ch','segments');
S = load(fullfile(source_dir,'ccf_preview_50ch.mat'));
C = load(fullfile(source_dir,'mccfj_composite_50ch.mat'), ...
    'dates','keep','raw_valid','reference_valid_segments','pair_window_count');
E = load(fullfile(source_dir,'edwav_screening.mat'),'segment_start','file_paths');
assert(numel(E.segment_start)==1,'Expected one demo segment.');
A = load(E.file_paths(1),'source_file','dasqt_full_channel_count');

assert(isequal(size(S.ccf_gather),[401 50]), ...
    'Expected the confirmed 50-channel, +/-1 s demo.');
assert(max(abs(S.ccf_time_s([1 end])-[-1;1]))<1e-9, ...
    'Expected CCF time endpoints -1 and +1 s.');
assert(isequal(size(S.spectrum),[numel(S.velocity) numel(S.frequency)]), ...
    'Spectrum dimensions must match its axes.');

fields = {'ccf_gather','ccf_time_s','offset_all','spectrum', ...
    'ridge_velocity','frequency','velocity','count_sum'};
for i = 1:numel(fields)
    R.(fields{i}) = S.(fields{i});
end
R.p = rmfield(S.p,{'dasqt_cache_dir','segment_inventory'});
R.config = jsondecode(fileread(fullfile(root,'configs','demo_small.json')));
R.dates = cellstr(C.dates);
R.keep = C.keep;
R.raw_valid = C.raw_valid;
R.reference_valid_segments = C.reference_valid_segments;
R.pair_window_count = C.pair_window_count;
R.channel_numbers = R.config.raw_channel_start + ...
    R.config.raw_channel_first0 + (0:R.p.n_station-1);
R.source_start_time = char(E.segment_start(1));
start_time = datetime(R.source_start_time,'InputFormat','yyyy-MM-dd HH:mm:ss');
R.source_end_time = char(start_time+seconds(R.p.segment_seconds), ...
    'yyyy-MM-dd HH:mm:ss');
[~,source_name,source_extension] = fileparts(A.source_file);
R.source_file = [source_name source_extension];
R.preprocessing_channel_count = A.dasqt_full_channel_count;
R.spectrum_quantity = 'abs(real(FJ.dsp))';

if ~isfolder(target_dir), mkdir(target_dir); end
if ~isfolder(cache_target), mkdir(cache_target); end
save(fullfile(target_dir,'result.mat'),'-struct','R','-v7');
copyfile(fullfile(source_dir,'mccfj_composite_50ch.png'), ...
    fullfile(target_dir,'preview.png'));
cache_files = dir(fullfile(source_dir,'dasqt_cache','segments','segment_*.mat'));
assert(numel(cache_files)==1,'Expected one preprocessed demo segment.');
copyfile(fullfile(cache_files(1).folder,cache_files(1).name), ...
    fullfile(cache_target,cache_files(1).name));
fprintf('Demo input cache, image, and numerical result exported.\n');
end
