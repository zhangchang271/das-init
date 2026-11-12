function report = validate_demo(candidate)
%VALIDATE_DEMO Compare a deployment against the confirmed real-data demo.
% A directory checks screening, sparse native CCF, and final observations.
% A MAT file checks the portable final-result interface only. No rescaling,
% transposition, or re-picking is performed to make a candidate agree.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin<1
    candidate = fullfile(root,'outputs','demo_sanjose_small');
end
candidate = char(candidate);
contract = jsondecode(fileread(fullfile(root,'docs','demo','contract.json')));
reference = load(fullfile(root,'docs','demo','result.mat'));
tol = contract.validation;
report = struct;
if isfolder(candidate)
    final_file = fullfile(candidate,'ccf_preview_50ch.mat');
    report.scope = 'screening, sparse native CCF, final observations';
else
    final_file = candidate;
    report.scope = 'final observations only';
end
assert(isfile(final_file),'das_init:MissingResult', ...
    'Result file not found: %s',final_file);
actual = load(final_file);

axes = {'ccf_time_s','offset_all','frequency','velocity'};
for i = 1:numel(axes)
    name = axes{i};
    require_field(actual,name);
    report.(name) = compare(actual.(name),reference.(name), ...
        name,0,tol.axis_absolute);
end
values = {'ccf_gather','spectrum'};
for i = 1:numel(values)
    name = values{i};
    require_field(actual,name);
    report.(name) = compare(actual.(name),reference.(name), ...
        name,tol.relative,tol.value_absolute);
end
require_field(actual,'ridge_velocity');
report.ridge_velocity = compare(actual.ridge_velocity, ...
    reference.ridge_velocity,'ridge_velocity',0,tol.ridge_absolute_m_per_s);
require_field(actual,'count_sum');
report.count_sum = compare(actual.count_sum,reference.count_sum, ...
    'count_sum',0,0);
report.ccf_symmetry = compare(actual.ccf_gather,flipud(actual.ccf_gather), ...
    'ccf_symmetry',tol.relative,tol.value_absolute);

if isfolder(candidate)
    checkpoints = load(fullfile(root,'docs','demo','checkpoints.mat'));
    screening = load(fullfile(candidate,'edwav_screening.mat'), ...
        'proxy','keep','raw_valid');
    for field = {'keep','raw_valid'}
        name = field{1};
        require_field(screening,name);
        report.(name) = compare(screening.(name),checkpoints.(name),name,0,0);
    end
    require_field(screening,'proxy');
    report.proxy = compare(screening.proxy,checkpoints.proxy, ...
        'proxy',tol.relative,tol.value_absolute);

    cache_file = fullfile(candidate,'ccf_cache','ccf_24h_2023-09-20.mat');
    cache = load(cache_file,'ccf','freq','ccr','count_sum');
    for field = {'ccf','freq','ccr','count_sum'}
        require_field(cache,field{1});
    end
    assert(isequal(size(cache.ccf),double(checkpoints.cache_size)), ...
        'das_init:Shape','cache_ccf: expected [%s], got [%s].', ...
        num2str(checkpoints.cache_size),num2str(size(cache.ccf)));
    assert(isequal(size(cache.freq),[size(cache.ccf,1) 1]), ...
        'das_init:Shape','cache freq must be a column matching cache_ccf rows.');
    assert(all(isfinite(cache.ccf(:))), ...
        'das_init:Nonfinite','cache_ccf contains NaN or Inf.');
    assert(iscell(cache.ccr) && isequal(size(cache.ccr),[50 6]), ...
        'das_init:Shape','cache ccr must be the original 50 x 6 pair cell.');
    ids = double(checkpoints.frequency_index1);
    report.cache_frequency = compare(cache.freq(ids), ...
        checkpoints.cache_frequency,'cache_frequency',0,tol.axis_absolute);
    report.cache_frequency_endpoints = compare(cache.freq([1 end]), ...
        checkpoints.cache_frequency_endpoints,'cache_frequency_endpoints', ...
        0,tol.axis_absolute);
    report.cache_ccf = compare(cache.ccf(ids,:),checkpoints.cache_ccf, ...
        'cache_ccf',tol.relative,tol.value_absolute);
    report.cache_count_sum = compare(cache.count_sum,checkpoints.count_sum, ...
        'cache_count_sum',0,0);
    report.pair_distance_m = compare(cell2mat(cache.ccr(:,1)), ...
        checkpoints.pair_distance_m,'pair_distance_m',0,tol.axis_absolute);
    pair_index1 = [cell2mat(cache.ccr(:,2)),cell2mat(cache.ccr(:,3))];
    report.pair_index1 = compare(pair_index1,checkpoints.pair_index1, ...
        'pair_index1',0,0);
end
report.passed = true;
fprintf('DEMO_VALIDATION_PASSED (%s)\n',report.scope);
end

function require_field(data,name)
assert(isfield(data,name),'das_init:MissingField','Missing field: %s',name);
end

function result = compare(actual,expected,name,relative,absolute)
assert(isnumeric(actual) || islogical(actual), ...
    'das_init:Type','%s must be a numeric or logical array.',name);
assert(isequal(size(actual),size(expected)), ...
    'das_init:Shape','%s: expected [%s], got [%s].', ...
    name,num2str(size(expected)),num2str(size(actual)));
a = double(actual);
b = double(expected);
assert(all(isfinite(a(:))),'das_init:Nonfinite','%s contains NaN or Inf.',name);
delta = a-b;
error_norm = norm(delta(:));
reference_norm = norm(b(:));
max_error = max(abs(delta(:)));
peak_reference = max(abs(b(:)));
assert(error_norm<=absolute*sqrt(numel(b))+relative*reference_norm && ...
    max_error<=absolute+relative*peak_reference, ...
    'das_init:Numeric', ...
    '%s: relative error %.6g, max error %.6g (rtol %.6g, atol %.6g).', ...
    name,error_norm/max(reference_norm,realmin),max_error,relative,absolute);
result.relative_error = error_norm/max(reference_norm,realmin);
result.max_absolute_error = max_error;
fprintf('%s: relative=%.3g, max=%.3g\n', ...
    name,result.relative_error,result.max_absolute_error);
end
