function quoted = shell_quote(value)
%SHELL_QUOTE Quote a literal argument for a POSIX shell.
value = char(value);
assert(isrow(value) && ~any(value==0 | value==10 | value==13), ...
    'Shell arguments must be one line without NUL characters.');
sq = char(39);
quoted = [sq strrep(value,sq,[sq char(34) sq char(34) sq]) sq];
end
