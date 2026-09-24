function bench_batch()
%BENCH_BATCH  Point d''entree du processus MATLAB detache.
addpath('common'); addpath('piste_B_nominal_correction');
diary(fullfile('results','bench_dt_log.txt')); diary on;
fprintf('DEMARRAGE %s\\n', datestr(now));
out = '';
n = 0;
while ~strcmp(out, 'TOUT TERMINE') && n < 100
  try
    out = bench_tick(100000);
  catch ME
    fprintf('ERREUR : %s\\n', ME.message);
    for q = 1:numel(ME.stack); fprintf('   %s ligne %d\\n', ME.stack(q).name, ME.stack(q).line); end
    break;
  end
  n = n + 1;
end
fprintf('FIN %s\\n', datestr(now));
diary off;
end
