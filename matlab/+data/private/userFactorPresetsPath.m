function p = userFactorPresetsPath()
%USERFACTORPRESETSPATH  Default location for the user factor-presets file:
%   fastener_factor_presets.json in data.userDataFolder(), the same folder
%   as the custom library, so the two always move together.
p = string(fullfile(char(data.userDataFolder()), "fastener_factor_presets.json"));
end
