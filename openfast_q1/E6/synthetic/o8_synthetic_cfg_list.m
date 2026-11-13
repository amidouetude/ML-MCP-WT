function cfgs = o8_synthetic_cfg_list(family, L_list)
%O8_SYNTHETIC_CFG_LIST  Intermediate configurations of spec_E6_solver_O8, in their order of
%measurement: cost_measurement_protocol.measurements.i_intermediate option (a) (supervisor decision
%28 of 03/11/2026) for C2 and C3, cost_measurement_protocol.amendment_7.C5_configurations for C5.
%
%   cfgs = o8_synthetic_cfg_list(family)          family 'C2', 'C3' or 'C5'
%   cfgs = o8_synthetic_cfg_list('C2', L_list)    C2 at the window lengths L_list with the same rule
%                                                 (tests: L = 34 gives the configuration of (i))
%
%   cfgs(k).id       identifier, for example 'C2_L16', 'C3_H64x2', 'C5_r128x128'
%   cfgs(k).family   'C2', 'C3' or 'C5'
%   cfgs(k).L        window length (C2), warm-up length (C3), [] for C5
%   cfgs(k).H, nl    hidden size and number of layers (C3), [] otherwise
%   cfgs(k).widths   hidden widths of the residual MLP (C5), [] otherwise
%   cfgs(k).dil      dilations of the TCN (C2), [] otherwise
%   cfgs(k).nz       state dimension: 4 L - 2 (C2 window, timing_E6_nlmpc.m l.279), 2 + 2 H nl (C3,
%                    l.380), 2 (C5)
%
%   C2 (i_intermediate options_considered (a)): L = 16, 8, 4, the other hyperparameters at their
%   largest value (kernel 3, 64 channels; spec_E5 l.39); dilations 1, 2, 4, ... with the smallest
%   number of blocks whose receptive field 1 + (k - 1) sum(dil) reaches L (spec_E5 C2_TCN, one
%   convolution per block as tcn_fwd of timing_E6_nlmpc.m l.314-327): [1 2 4 8] for L = 16 (31),
%   [1 2 4] for L = 8 (15), [1 2] for L = 4 (7); L = 34 gives [1 2 4 8 16] (63), the timing value.
%   C3 (i_intermediate options_considered (a)): (H, layers) in decreasing nz, the configuration
%   measured in (i) (128, 2) excluded and, at equal nz, 2 layers before 1 layer (the order written
%   by the supervisor on 13/11/2026: (64, 2), (128, 1), (32, 2), ...): (64, 2), (128, 1), (32, 2),
%   (64, 1), (16, 2), (32, 1); (16, 1) is measured in (i) (2.209 h); warm-up L = 34.
%   C5 (amendment_7.C5_configurations): 3 x 128, 2 x 128, 3 x 64, 2 x 64, 3 x 32, 2 x 32, 1 x 128,
%   3 x 16, 1 x 64, 2 x 16, 1 x 32, 1 x 16.

switch family
    case 'C2'
        if nargin < 2
            L_list = [16 8 4];
        end
        cfgs = struct('id', {}, 'family', {}, 'L', {}, 'H', {}, 'nl', {}, 'widths', {}, 'dil', {}, 'nz', {});
        for k = 1:numel(L_list)
            L = L_list(k);
            cfgs(end+1) = struct('id', sprintf('C2_L%d', L), 'family', 'C2', 'L', L, 'H', [], 'nl', [], ...
                                 'widths', [], 'dil', tcn_dilations(3, L), 'nz', 4*L - 2); %#ok<AGROW>
        end
    case 'C3'
        hl = [64 2; 128 1; 32 2; 64 1; 16 2; 32 1];
        cfgs = struct('id', {}, 'family', {}, 'L', {}, 'H', {}, 'nl', {}, 'widths', {}, 'dil', {}, 'nz', {});
        for k = 1:size(hl, 1)
            cfgs(end+1) = struct('id', sprintf('C3_H%dx%d', hl(k, 1), hl(k, 2)), 'family', 'C3', 'L', 34, ...
                                 'H', hl(k, 1), 'nl', hl(k, 2), 'widths', [], 'dil', [], ...
                                 'nz', 2 + 2*hl(k, 1)*hl(k, 2)); %#ok<AGROW>
        end
    case 'C5'
        w_list = {[128 128 128], [128 128], [64 64 64], [64 64], [32 32 32], [32 32], 128, [16 16 16], 64, ...
                  [16 16], 32, 16};
        cfgs = struct('id', {}, 'family', {}, 'L', {}, 'H', {}, 'nl', {}, 'widths', {}, 'dil', {}, 'nz', {});
        for k = 1:numel(w_list)
            cfgs(end+1) = struct('id', ['C5_r' strjoin(arrayfun(@num2str, w_list{k}, 'UniformOutput', false), 'x')], ...
                                 'family', 'C5', 'L', [], 'H', [], 'nl', [], 'widths', w_list{k}, 'dil', [], ...
                                 'nz', 2); %#ok<AGROW>
        end
    otherwise
        error('o8_synthetic_cfg_list:family', 'family must be ''C2'', ''C3'' or ''C5''.');
end
end

function dil = tcn_dilations(k, L)
% dilations 1, 2, 4, ... with the smallest number of blocks whose receptive field reaches L
% (spec_E5 C2_TCN); receptive field of one causal convolution per block: 1 + (k - 1) sum(dil)
dil = 1;
while 1 + (k - 1)*sum(dil) < L
    dil = [dil, 2*dil(end)]; %#ok<AGROW>
end
end
