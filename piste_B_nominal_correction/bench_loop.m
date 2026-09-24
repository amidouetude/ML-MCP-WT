function bench_loop()
%BENCH_LOOP  Enchaine les tranches jusqu''a completion du benchmark A/B.
addpath('common'); addpath('piste_B_nominal_correction');
out = '';
n = 0;
while ~strcmp(out, 'TOUT TERMINE') && n < 400
  out = bench_tick(600);
  n = n + 1;
end
end
