function [window_data,window_time_s] = crop_ccf_window(data,time_s,half_window_s)
%CROP_CCF_WINDOW Keep only CCF samples inside a symmetric time window.
validateattributes(data,{'numeric'},{'2d'});
validateattributes(time_s,{'numeric'},{'vector','real','finite'});
validateattributes(half_window_s,{'numeric'}, ...
    {'scalar','real','finite','positive'});
assert(size(data,1)==numel(time_s), ...
    'Time vector length must match the CCF row count.');
keep = abs(time_s(:))<=half_window_s;
window_data = data(keep,:);
window_time_s = time_s(keep);
end
