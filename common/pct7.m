function q = pct7(x, p)
%PCT7  Quantile, convention « type 7 » (interpolation lineaire).
%
%   q = pct7(x, p)   avec p dans [0,1]
%
%   POURQUOI CETTE FONCTION PLUTOT QUE quantile() — decision du 23/09/2026
%
%   1. quantile() appartient a Statistics and Machine Learning Toolbox.
%      L'outillage de reproductibilite ne doit pas dependre implicitement
%      d'une toolbox : si elle manque, la campagne meurt en cours de bras,
%      apres des heures.
%
%   2. Raison decisive : la CONVENTION. MATLAB quantile() utilise les
%      positions (i-0.5)/n ; numpy.quantile utilise par defaut le « type 7 »,
%      h = 1 + (n-1)p. Les deux donnent des valeurs DIFFERENTES sur un meme
%      echantillon. Or verifier_chaine.py recalcule les valeurs publiees avec
%      numpy. Employer quantile() cote MATLAB ferait echouer la verification
%      sur Q1 et Q3 sans qu'aucune mesure ne soit en cause.
%
%      pct7 reproduit exactement numpy.quantile(..., method='linear').
%      La convention est ainsi FIGEE DANS LE PROTOCOLE, des deux cotes.
%
%   3. La mediane est identique dans les deux conventions ; seuls les
%      quartiles divergent. C'est pourquoi le defaut n'aurait ete vu qu'au
%      moment de verifier Q1/Q3 — c'est-a-dire trop tard.
%
%   Reference : Hyndman & Fan (1996), definition 7.

x = sort(x(:));
n = numel(x);
if n == 0, q = NaN; return; end
if n == 1, q = x(1); return; end

h  = 1 + (n - 1) * p;
lo = floor(h);
hi = ceil(h);
lo = max(1, min(n, lo));
hi = max(1, min(n, hi));
if lo == hi
    q = x(lo);
else
    q = x(lo) + (h - lo) * (x(hi) - x(lo));
end
end
