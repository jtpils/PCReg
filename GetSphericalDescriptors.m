clear all
close all

%% TODOs
% - implement better keypoint detector?
% - organize code

%% define method for sampling points (keypoint detection)
% 'UNIFORM' for regular grid (uniform sampling)
% 'UNIFORM_SAME' for the same regular grid on all point clouds
% 'RANDOM_POINTS' for random points in point cloud
% 'RANDOM_UNIFORM' for random uniformly distributed points
% 'ALL' for all points in point cloud
sampling_method = 'RANDOM_UNIFORM';

% if 'UNIFORM' or 'UNIFORM_SAME' or 'RANDOM_UNIFORM' specify density of sphere-grid
d = 0.3; % 0.4, spacing of spheres along each axis (0.3 is better, 0.2 takes forever)

% margin: samples outside the box can be useful (should be equal to or > R)
margin = 3.5;

%if 'RANDOM_POINTS' specify fraction of points considered
sample_frac = 0.2;

%% READ in aligned surface and model crop
path = 'Data/PointClouds/';
pcSurface = pcread(strcat(path, 'Surface_DS2_alignedM.pcd'));
pcModel = pcread(strcat(path, 'GoodCropSmoothUp3_large.pcd'));
pcRand = pcread(strcat(path, 'RandCropSmoothUp3.pcd'));

% recommended: center point clouds
SHIFT = false; % 'true' destroys alignment, if aligned

% turn off to omit matching with random crop
RAND_CROP = false;

if SHIFT
    pcSurface = centerPointCloud(pcSurface);
    pcModel = centerPointCloud(pcModel);
    pcRand = centerPointCloud(pcRand);
end

% DEBUG: manually align now REMOVE for normal experiments!!!
%load('Tform_align2.mat');
%pcSurface = pctransform(pcSurface, affine3d(Tform_align2));
%pcSurface = centerPointCloud(pcSurface);

%% define locations of spheres for local descriptors
if strcmp(sampling_method, 'UNIFORM_SAME')
    XLimits = [min([pcSurface.XLimits(1), pcModel.XLimits(1), pcRand.XLimits(1)]), ...
                max([pcSurface.XLimits(2), pcModel.XLimits(2), pcRand.XLimits(2)])];
    YLimits = [min([pcSurface.YLimits(1), pcModel.YLimits(1), pcRand.YLimits(1)]), ...
                max([pcSurface.YLimits(2), pcModel.YLimits(2), pcRand.YLimits(2)])];
    ZLimits = [min([pcSurface.ZLimits(1), pcModel.ZLimits(1), pcRand.ZLimits(1)]), ...
                max([pcSurface.ZLimits(2), pcModel.ZLimits(2), pcRand.ZLimits(2)])];

    % create meshgrid of points    
    x = XLimits(1):d:XLimits(2);
    y = YLimits(1):d:YLimits(2);
    z = ZLimits(1):d:ZLimits(2);
    [X,Y,Z] = meshgrid(x,y,z);
    sample_pts = cat(4, X, Y, Z);
    sample_pts = reshape(sample_pts, [], 3);
    
    sample_ptsSurface = sample_pts;
    sample_ptsModel = sample_pts;
    sample_ptsRand = sample_pts;
    
elseif strcmp(sampling_method, 'UNIFORM')    
    sample_ptsSurface = pcUniformSamples(pcSurface, d);
    sample_ptsModel = pcUniformSamples(pcModel, d);
    sample_ptsRand = pcUniformSamples(pcRand, d);
    
elseif strcmp(sampling_method, 'RANDOM_UNIFORM')    
    % use margin for surface, but not for model
    sample_ptsSurface = pcRandomUniformSamples(pcSurface, d, margin);
    sample_ptsModel = pcRandomUniformSamples(pcModel, d, -margin);
    sample_ptsRand = pcRandomUniformSamples(pcRand, d, -margin);
    
elseif strcmp(sampling_method, 'RANDOM_POINTS')    
    sample_ptsSurface = pcRandomPoints(pcSurface, sample_frac);
    sample_ptsModel = pcRandomPoints(pcModel, sample_frac);
    sample_ptsRand = pcRandomPoints(pcRand, sample_frac);
    
elseif strcmp(sampling_method, 'ALL')    
    sample_ptsSurface = pcSurface.Location;
    sample_ptsModel = pcModel.Location;
    sample_ptsRand = pcRand.Location;
    
else
    error('Specified Method "%s" not yet implemented or does not exist', sampling_method);
end

%% get local descriptors for each model

% define which descriptor to use
% 'Moment' --> using 1st to 4th order moments with LRF
% 'Rotational' --> inherently rotation invariant (radial frequencies)
% 'Histogram' --> Spacial spherical histogram
descriptor = 'Histogram';

% if descriptor is 'Moment' optionally align to a local reference frame
descOpt.ALIGN_POINTS = true;

% optional: don't use first moment and center by this instead
descOpt.CENTER = false;

% specify minimum number of points that has to be in sphere
descOpt.min_pts = 500; % 51 / 101 / 500

% specify maximum number of points that can be in sphere
descOpt.max_pts = 8000; % inf / 3*min_pts / 8*min_pts

% specify radius of spheres (local descriptor neighborhood)
descOpt.R = 3.5; % 1.5 / 2.5 / 3.5

% specify the reject threshold for eccentricity (covar-eigenvalues), value
% must be >= 1 
descOpt.thVar = [3, 1.5]; % [1.5, 1.5] / [4, 2] 

% specify number of nearest neighbors (KNN) to use for local reference
% frame. Number should be <= min_points, or write 'all'
% if k is 'all', then points need not be sorted - faster. 
descOpt.k = 'all';

% get points from pointclouds
ptsModel = pcModel.Location;
ptsRand = pcRand.Location;
ptsSurface = pcSurface.Location;

% calculate the descriptos with the specified method
if strcmp(descriptor, 'Moment')    
    [featModel, descModel, angModel] = ...
            getMomentDescriptors(ptsModel, sample_ptsModel, descOpt);
    if RAND_CROP
        [featRand, descRand, angRand] = ...
            getMomentDescriptors(ptsRand, sample_ptsRand, descOpt);
    end
    [featSurface, descSurface, angSurface] = ...
        getMomentDescriptors(ptsSurface, sample_ptsSurface, descOpt);        
elseif strcmp(descriptor, 'Rotational')    
    [featModel, descModel] =  ...
        getRotationalDescriptors(ptsModel, sample_ptsModel, descOpt);
    if RAND_CROP
        [featRand, descRand] = ...
            getRotationalDescriptors(ptsRand, sample_ptsRand, descOpt);
    end
    [featSurface, descSurface] = ...
        getRotationalDescriptors(ptsSurface, sample_ptsSurface, descOpt);
elseif strcmp(descriptor, 'Histogram')    
    [featModel, descModel] = ...
        getSpacialHistogramDescriptors(ptsModel, sample_ptsModel, descOpt);
    if RAND_CROP
        [featRand, descRand] = ...
            getSpacialHistogramDescriptors(ptsRand, sample_ptsRand, descOpt);
    end
    [featSurface, descSurface] = ...
        getSpacialHistogramDescriptors(ptsSurface, sample_ptsSurface, descOpt);        
else
    error('Descriptor method must be either Moment or Rotational');
end


%% descriptor weighting, normalization, and matching options

% optional: un-normalize descriptors before matching
UNNORMALIZE = true;
norm_factor = 2; % 2

% optional: raise descriptors to power to change L1 distance metric
% use only with L1-distance
CHANGE_METRIC = true;
metric_factor = 0.45; % 0.4 / 0.45

% mahalanobis distance? Similar to L2. Don't combine with the
% change metric!
MAHALANOBIS = false;

% Matching Algorithm Parameters
par.Method = 'Approximate'; % 'Exhaustive' (default) or 'Approximate'
par.MatchThreshold = 10; % 1.0 (default) Percent Value (0 - 100) for distance-reject
par.MaxRatio = 0.98; % 0.6 (default) nearest neighbor ambiguity rejection
par.Metric =  'SAD'; % SSD (default) for L2, SAD for L1
par.Unique = true; % true: 1-to-1 mapping only, else set false (default)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Apply the normalization and match %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% --- Un-normalization by adding constant element to end --- %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if UNNORMALIZE
    % get average descriptor length
    avg_desc_len = mean(vecnorm([descSurface; descModel], 1, 2));
    descSurfaceN = [descSurface,  norm_factor*avg_desc_len*ones(size(descSurface, 1), 1)]; 
    descModelN = [descModel,  norm_factor*avg_desc_len*ones(size(descModel, 1), 1)];
    if RAND_CROP
        descRandN = [descRand,  norm_factor*avg_desc_len*ones(size(descRand, 1), 1)];
    end
else
    descSurfaceN = descSurface;
    descModelN = descModel;
    if RAND_CROP
        descRandN = descRand;
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% --- raise descriptors to power before L1-matching --- %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if CHANGE_METRIC
    descSurfaceC = descSurfaceN.^metric_factor;
    descModelC = descModelN.^metric_factor;
    if RAND_CROP
        descRandC = descRandN.^metric_factor;
    end
else
    descSurfaceC = descSurfaceN;
    descModelC = descModelN;
    if RAND_CROP
        descRandC = descRandN;
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Modify descriptors based on their variance --> Mahalanobis Distance
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if MAHALANOBIS
    % get covariance matrix of all descriptors 
    S_Model = cov([descModelC; descSurfaceC]);

    % get square root, so that A'*A = S (S is hermitian)
    A_Model = real(S_Model^0.5);

    % Modify Descriptors accordingly
    dMM = descModelC*A_Model;
    dSM = descSurfaceC*A_Model;

    % same procedure for random crop
    if RAND_CROP
        S_Rand = cov([descRandC; descSurfaceC]);
        A_Rand = real(S_Rand^0.5);
        dRR = descRandC*A_Rand;
        dSR = descSurfaceC*A_Rand;
    end
else
    dSM = descSurfaceC;
    dMM = descModelC;
    if RAND_CROP
        dSR = descSurfaceC;
        dRR = descRandC;
    end
end

% clear everything that is not needed anymore (intermediate variables)
clear descSurfaceC descModelC descRandC
clear descSurfaceN descModelN descRandN
clear S_Model A_Model

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Match features between Surface and Model / Random Crop %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

matchesModel = matchFeatures(dSM, dMM, ...
        'Method', par.Method, ...
        'MatchThreshold', par.MatchThreshold, ... 
        'MaxRatio', par.MaxRatio, ... 
        'Metric', par.Metric, ...
        'Unique', par.Unique); 
if RAND_CROP
    matchesRand = matchFeatures(dSR, dRR, ...
            'Method', par.Method, ...
            'MatchThreshold', par.MatchThreshold, ... 
            'MaxRatio', par.MaxRatio, ... 
            'Metric', par.Metric, ...
            'Unique', par.Unique); 
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Determine Inliers %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Get distance between matching points
% this makes sense, because the pointclouds are already aligned. The
% distance between matching INLIERS of the model will thus be small and a
% simple distance threshold can be used to determine whether a match is an
% inlier 

% maxDist specifies matching distance to count inliers 
maxDist = 1.5; 

% matches of surface and model
loc1S = featSurface(matchesModel(:, 1), :);
loc1M = featModel(matchesModel(:, 2), :);
d1 = vecnorm(loc1M - loc1S, 2, 2);
inlier_idx = find(d1 < maxDist);
inliers1 = length(inlier_idx);

% precision
inliersPrecision = inliers1/size(d1, 1)*100;

if RAND_CROP
    % matches of surface and random crop
    loc2S = featSurface(matchesRand(:, 1), :);
    loc2M = featRand(matchesRand(:, 2), :);
    d2 = vecnorm(loc2M - loc2S, 2, 2);
    inliers2 = length(find(d2 <= maxDist));
end

%% helper function: center PC (0,0) in middle of crop
function pc_out = centerPointCloud(pc)
    % translation of pointcloud
    T = [(pc.XLimits(1) + pc.XLimits(2))/2, ...
        (pc.YLimits(1) + pc.YLimits(2))/2, ...
        (pc.ZLimits(1) + pc.ZLimits(2))/2];
    A = eye(4);
    A(4, 1:3) = -T;
    tform = affine3d(A);
    pc_out = pctransform(pc, tform);
end

%% helper function: uniformly sample point cloud
function sample_pts = pcUniformSamples(pcIn, d) 
    % create meshgrid of points	  
    x = pcIn.XLimits(1):d:pcIn.XLimits(2);
    y = pcIn.YLimits(1):d:pcIn.YLimits(2);
    z = pcIn.ZLimits(1):d:pcIn.ZLimits(2);
    [X,Y,Z] = meshgrid(x,y,z);
    sample_pts = cat(4, X, Y, Z);
    sample_pts = reshape(sample_pts, [], 3);
end

%% helper function: random-uniformly sample point cloud
function sample_pts = pcRandomUniformSamples(pcIn, d, margin)
    % calculate num_pts to sample based on size of pointcloud and d
    rangeX = pcIn.XLimits(2) - pcIn.XLimits(1) + 2*margin;
    rangeY = pcIn.YLimits(2) - pcIn.YLimits(1) + 2*margin;
    rangeZ = pcIn.ZLimits(2) - pcIn.ZLimits(1) + 2*margin;
    num_pts = round((rangeX * rangeY * rangeZ) / (d^3));
          
    % sample enough random uniformly distributed numbers in range [0, 1]
    sample_pts = rand(num_pts, 3); 
    
    % scale numbers so that they fit into the correct range
    sample_pts = sample_pts .* [rangeX, rangeY, rangeZ];
    sample_pts = sample_pts + ...
        [pcIn.XLimits(1), pcIn.YLimits(1), pcIn.ZLimits(1)] - margin;
end

%% helper function: select random points from point cloud
function sample_pts = pcRandomPoints(pcIn, sample_frac)
    nPoints = size(pcIn.Location, 1);
    sIdx = randsample(nPoints,floor(nPoints*sample_frac));
    sample_pts = pcIn.Location(sIdx, :);
end