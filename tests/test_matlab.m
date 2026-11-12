function tests = test_matlab
%TEST_MATLAB Small configuration and PSD checks, independent of the full day.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'matlab'),fullfile(root,'vendor','matlab'));
testCase.TestData.root = root;
end

function testJsonDefaultsAndStages(testCase)
root = testCase.TestData.root;
cfg = workflow_config(fullfile(root,'configs','san_jose.example.json'));
verifyEqual(testCase,cfg.Fs,200);
verifyEqual(testCase,cfg.segment_seconds,600);
verifyEqual(testCase,cfg.ccf_frequency_normalization,'PSD');
verifyEqual(testCase,cfg.station_x,0:499);
verifyEqual(testCase,cfg.velocity,(100:800).');
verifyEqual(testCase,cfg.stage,'preview');
verifyEqual(testCase,cfg.frequency_range,[1 15]);
verifyEqual(testCase,cfg.ccf_maximum_frequency,30);
verifyFalse(testCase,cfg.apply_gw_mute);
verifyEqual(testCase,cfg.ccf_window_half_s,1);
verifyEqual(testCase,cfg.fj_reliable_range,[3 12]);
verifyEqual(testCase,cfg.frequency_step,0.1);
verifyEqual(testCase,cfg.pick_velocity_range,[140 450]);
verifyEqual(testCase,cfg.pick_seed_frequency,10);
demo = workflow_config(fullfile(root,'configs','demo_small.json'));
verifyEqual(testCase,demo.n_station,50);
verifyEqual(testCase,demo.max_segments,1);
verifyEqual(testCase,demo.minimum_segments_per_window,1);
verifyTrue(testCase,demo.dasqt_common_mode_removal);
verifyEqual(testCase,demo.ccf_window_half_s,1);
verifyFalse(testCase,demo.dasqt_make_cache);
verifyEqual(testCase,demo.dasqt_cache_dir, ...
    fullfile(root,'configs','..','data','demo_sanjose_50ch'));
demo_files = dir(fullfile(demo.dasqt_cache_dir,'segments','segment_*.mat'));
verifyEqual(testCase,numel(demo_files),1);
demo_segment = load(fullfile(demo_files(1).folder,demo_files(1).name), ...
    'wave','raw_valid','dasqt_full_channel_count');
verifySize(testCase,demo_segment.wave,[120000 50]);
verifyTrue(testCase,all(demo_segment.raw_valid(:)));
verifyEqual(testCase,demo_segment.dasqt_full_channel_count,int32(500));
cfg = workflow_config(fullfile(root,'configs','san_jose.example.json'),'pick');
verifyEqual(testCase,cfg.stage,'pick');
end

function testCcfWindowCrop(testCase)
time_s = (-1.5:0.1:1.5).';
gather = repmat((1:numel(time_s)).',1,2);
[window,window_time] = crop_ccf_window(gather,time_s,1);
verifyEqual(testCase,window,gather(abs(time_s)<=1,:));
verifyEqual(testCase,window_time,time_s(abs(time_s)<=1));
verifyEqual(testCase,window_time([1 end]),[-1;1]);
end

function testPsdUsesActiveArrayPower(testCase)
% Compare with the array-mean PSD formula, including invalid-channel counts.
% Scaling every active waveform equally must leave PSD CCF unchanged.
rng(47);
wave = randn(2000,4).*[1 3 0.4 1];
wave(:,4) = 0;
geometry = [0:3;zeros(1,4)];
options = {'AX','xyz','CL',2000,'OL',0,'FL',0,'NT','No', ...
    'NF','PSD','FM',30,'FD',1,'TP','No','GPU','No'};
a = mCCFJ.correlate(wave,geometry,200,options{:});
b = mCCFJ.correlate(7*wave,geometry,200,options{:});
X = fft(wave,2000,1)/2000;
X = X(1:1001,:);
X(2:end-1,:) = 2*X(2:end-1,:);
frequency_id = a.freq<=30;
X = X(frequency_id,:);
power = mean(abs(X(:,1:3)).^2,2);
denominator = power + 1e-6*mean(power);
first = cell2mat(a.ccr(:,2));
second = cell2mat(a.ccr(:,3));
expected = zeros(size(a.ccf));
expected(frequency_id,:) = conj(X(:,first)).*X(:,second)./denominator;
verifyEqual(testCase,a.ccf,expected,'AbsTol',1e-12);
verifyEqual(testCase,a.info.cstack,double((first~=4 & second~=4).'));
verifyEqual(testCase,a.ccf,b.ccf,'AbsTol',1e-12);
verifyEqual(testCase,a.info.cstack,b.info.cstack);
end

function testShellArgumentIsLiteral(testCase)
text = ['a b' char(39) '$HOME`command`'];
[status,result] = system(['printf %s ' shell_quote(text)]);
verifyEqual(testCase,status,0);
verifyEqual(testCase,result,text);
end
