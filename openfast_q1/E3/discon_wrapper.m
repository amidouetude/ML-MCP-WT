function out = discon_wrapper(mode, varargin)
%DISCON_WRAPPER  DISCON.dll called from MATLAB through its Bladed interface (openfast_q1/E3/spec_E3W.yaml).
%
%   discon_wrapper('init', dll, hfile)         load the library with the default options of loadlibrary
%                                              (spec_E3W wrapper.library, amendment 2), check that
%                                              libfunctions lists DISCON (wrapper.call), reset the state
%   c = discon_wrapper('step', t, bp1, gs, hwv)
%        t   time (s); bp1 BldPitch1 (rad); gs GenSpeed (rad/s); hwv HorWindV (m/s)
%        fills wrapper.records_in, calls DISCON, applies wrapper.checks, computes wrapper.records_out:
%        c = [pitch command (rad); generator torque (N-m); electrical power (W);
%             record 45 (rad); record 47 (N-m); aviFAIL]
%   discon_wrapper('final')                    call with status -1 (wrapper.records_in, record 1), then
%                                              unload the library (wrapper.instance)
%   s = discon_wrapper('stats')                number of calls, wall time of the calls, warnings
%
%   The state between two calls (avrSWAP, record 35, status) is kept here (wrapper.instance).
%   The final call changes only record 1, as ServoDyn (BladedInterface.f90 l.823-825).

LIB      = 'DISCON';                  % library name given by loadlibrary (wrapper.library)
NSWAP    = 1000;                      % wrapper.avrSWAP
DT       = 0.00625;                   % s, wrapper.records_in record 3 and wrapper.period
NUMBL    = 3;                         % wrapper.records_in record 61
INFILE   = 'DISCON.IN';               % wrapper.strings (accINFILE)
ROOTNAME = '5MW_Land_DLL_WTurb.SrvD'; % wrapper.root_name
MSGLEN   = 8196;                      % wrapper.record_49 (buffer of MSGLEN + 1 characters)
GENEFF   = 0.944;                     % wrapper.records_out (electrical power)

persistent S
switch mode
    case 'init'
        [dll, hfile] = varargin{:};
        if libisloaded(LIB), error('discon_wrapper:loaded', 'Library %s is already loaded.', LIB); end
        loadlibrary(dll, hfile);
        if ~any(strcmp(libfunctions(LIB), 'DISCON'))
            unloadlibrary(LIB);
            error('discon_wrapper:symbol', 'libfunctions does not list DISCON (spec_E3W wrapper.call).');
        end
        S = struct('swap', zeros(NSWAP, 1, 'single'), 'status', 0, 'genstate', 1, ...
                   'ncalls', 0, 'wall_s', 0, 'warnings', {{}});
        out = [];

    case 'step'
        [t, bp1, gs, hwv] = varargin{:};
        w = S.swap;
        w(1)  = S.status;                 % 0 first call, 1 then (BladedInterface.f90 l.93-95)
        w(2)  = t;
        w(3)  = DT;
        w(4)  = bp1;                      % records 4, 33, 34 = BldPitch1 (wrapper.records_in)
        w(33) = bp1;
        w(34) = bp1;
        w(10) = 0;
        w(20) = gs;
        w(27) = hwv;
        w(35) = S.genstate;               % generator contactor returned by the previous call (initial 1)
        w(49) = MSGLEN + 1;
        w(50) = numel(INFILE) + 1;
        w(51) = numel(ROOTNAME) + 1;
        w(61) = NUMBL;
        [w, fail, S] = call(LIB, w, INFILE, ROOTNAME, MSGLEN, S);
        S.swap = w;  S.status = 1;
        S.genstate = double(w(35));
        % wrapper.checks (BladedInterface.f90 l.1160-1171 and l.1262)
        if round(w(55)) ~= 0 || round(w(56)) ~= 0
            error('discon_wrapper:override', 'Record 55 or 56 is not 0 at t = %.5f s.', t);
        end
        if S.genstate ~= 0 && S.genstate ~= 1
            error('discon_wrapper:contactor', 'Record 35 is %g at t = %.5f s.', S.genstate, t);
        end
        % wrapper.records_out
        pitch = double(w(45));                                    % collective (BladedInterface.f90 l.1149)
        if S.genstate ~= 0, tq = double(w(47)); else, tq = 0; end  % ServoDyn.f90 l.5962-5970
        if tq >= 0, pe = tq*gs*GENEFF; else, pe = tq*gs/GENEFF; end % ServoDyn.f90 l.6004-6007
        out = [pitch; tq; pe; double(w(45)); double(w(47)); double(fail)];

    case 'final'
        w = S.swap;
        w(1) = -1;                        % final call (BladedInterface.f90 l.823-825)
        [w, ~, S] = call(LIB, w, INFILE, ROOTNAME, MSGLEN, S);
        S.swap = w;
        unloadlibrary(LIB);
        out = [];

    case 'stats'
        out = struct('ncalls', S.ncalls, 'wall_s', S.wall_s, 'warnings', {S.warnings});

    otherwise
        error('discon_wrapper:mode', 'Unknown mode %s.', mode);
end

end

% =============================================================================================
function [w, fail, S] = call(lib, w, infile, rootname, msglen, S)
% one call of DISCON; aviFAIL < 0 stops, aviFAIL > 0 is recorded (spec_E3W wrapper.checks)
t0 = tic;
[w, fail, ~, ~, msg] = calllib(lib, 'DISCON', w, int32(0), infile, rootname, blanks(msglen));
S.wall_s = S.wall_s + toc(t0);
S.ncalls = S.ncalls + 1;
msg = strtrim(char(msg));
if fail < 0
    error('discon_wrapper:fail', 'DISCON returned aviFAIL = %d at status %g: %s', fail, w(1), msg);
elseif fail > 0
    S.warnings{end+1} = sprintf('t = %.5f s: %s', w(2), msg);
end
end
