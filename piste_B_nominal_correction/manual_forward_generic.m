function y = manual_forward_generic(x_row, manual_W, manual_b, manual_act)
% MANUAL_FORWARD_GENERIC  Forward pass through a sequential feedforward
% MLP using plain matrix multiplication, given weights/biases/
% activations extracted by extract_dlnetwork_generic.m. NEVER calls
% predict() or touches a dlnetwork/dlarray object.
%
%   y = manual_forward_generic(x_row, manual_W, manual_b, manual_act)
%
%   INPUTS
%     x_row       [1 x n_in]  row vector, normalised input features
%     manual_W    {1xL} cell array of weight matrices
%     manual_b    {1xL} cell array of bias vectors
%     manual_act  {1xL} cell array of activation names
%
%   OUTPUT
%     y   [1 x n_out]  row vector, network output (before de-normalisation)

h = x_row(:);   % column vector

for i = 1:numel(manual_W)
    h = manual_W{i} * h + manual_b{i};
    switch manual_act{i}
        case 'tanh'
            h = tanh(h);
        case 'relu'
            h = max(h, 0);
        case 'linear'
            % no-op
        otherwise
            error('Unknown activation "%s" in manual_forward_generic.', manual_act{i});
    end
end

y = h';   % row vector

end
