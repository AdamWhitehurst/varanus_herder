local VranherdClass = class()
local ShepherdClass = require ('stonehearth.jobs.shepherd.shepherd')
radiant.mixin(VranherdClass, ShepherdClass)
-- promote_to vranherd:jobs:vranherd
return VranherdClass
