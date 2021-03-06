------------------------------------------------------------------------
--[[ HyperOptimizer ]]--
-- Samples hyperparameters from a HyperparamSampler and 
-- passes these to a DatasourceFactory and ExperimentFactory to 
-- generate an Experiment wich is run until it terminates (returns) and
-- then the cyle starts again.
------------------------------------------------------------------------
local HyperOptimizer = torch.class("dp.HyperOptimizer")
HyperOptimizer.isHyperOptimizer = true

function HyperOptimizer:__init(config)
   local args, collection_name, hyperparam_sampler, experiment_factory, 
         datasource_factory, logger, namespace = xlua.unpack(
      {config or {}},
      'HyperOptimizer', nil,
      {arg='collection_name', type='string', req=true,
       help='identifies the collection of experiments'},
      {arg='hyperparam_sampler', type='dp.HyperparamSampler', req=true},
      {arg='experiment_factory', type='dp.ExperimentFactory', req=true},
      {arg='datasource_factory', type='dp.DatasourceFactory', req=true},
      {arg='logger', type='dp.Logger', help='defaults to dp.FileLogger'}
   )
   self._collection_name = collection_name
   self._hp_sampler = hyperparam_sampler
   self._xp_factory = experiment_factory
   self._ds_factory = datasource_factory
   self._logger = logger or dp.FileLogger()
   math.randomseed(os.time())
end

--generates globally unique experiment ID
function HyperOptimizer:nextID()
   return dp.ObjectID(dp.uniqueID(self._collection_name))
end

function HyperOptimizer:hyperReport(id, hyperparam)
   return {
      experiment_id = id:name();
      hyperparam = hyperparam,
      collection_name = self._collection_name,
      hyperparam_sampler = self._hp_sampler:hyperReport(),
      experiment_factory = self._xp_factory:hyperReport(),
      datasource_factory = self._ds_factory:hyperReport()
   }
end

function HyperOptimizer:run()
   while true do
      -- sample hyperparameters 
      local hp = self._hp_sampler:sample()
      -- assign a unique id
      local id = self:nextID()
      -- build datasource
      local ds = self._ds_factory:build(hp)
      local ds_name = hp.datasource
      hp.datasource = ds
      -- build experiment
      local xp = self._xp_factory:build(hp, id)
      hp.datasource = ds_name
      -- setup experiment (required for setting up logger)
      xp:setup(ds)
      -- log hyper-report
      self._logger:logHyperReport(self:hyperReport(id, hp))
      -- run the experiment on the datasource
      xp:run(ds)
      -- TODO : feedback hyperexperiment to HyperparamSampler
   end
end
