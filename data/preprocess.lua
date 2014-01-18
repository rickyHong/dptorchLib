require 'torch'
require 'image'
require 'paths'


------------------------------------------------------------------------
-- TODO : 
--- Preprocessor.__init should have a switch to determine if it is
--- to be applied to inputs, targets or both. Default is inputs only.
--- Unit tests. Start with standardize
------------------------------------------------------------------------

--[[
Abstract class.

An object that can preprocess a dataset.

Preprocessing a dataset implies changing the data that
a dataset actually stores. This can be useful to save
memory--if you know you are always going to access only
the same processed version of the dataset, it is better
to process it once and discard the original.

Preprocessors are capable of modifying many aspects of
a dataset. For example, they can change the way that it
converts between different formats of data. They can
change the number of examples that a dataset stores.
In other words, preprocessors can do a lot more than
just example-wise transformations of the examples stored
in the dataset.

function Preprocess:__init(...)
   
end
]]--
local Preprocess = torch.class("dp.Preprocess")
Preprocess.isPreprocess = true

--[[
datatensor: The DataTensor to act upon. An instance of dp.DataTensor.

can_fit: If True, the Preprocess can adapt internal parameters
         based on the contents of dataset.

Typical usage:
    # Learn PCA preprocessing and apply it to the training set
    train_set = MyDataset{which_set='train'}
    my_pca_preprocess:apply(train_set)
    # Now apply the same transformation to the test set
    test_set = MyDataset{which_set='valid'}
    my_pca_preprocess:apply(test_set)
]]--
function Preprocess:apply(datatensor, can_fit)
   error("Preprocessor subclass does not implement an apply method.")
end


-----------------------------------------------------------------------
-- Pipeline : A Preprocessor that sequentially applies a list
-- of other Preprocessors.
-----------------------------------------------------------------------
local Pipeline = torch.class("dp.Pipeline", "dp.Preprocess")
Pipeline.isPipeline = true

function Pipeline:__init(items)
   self._items = items or {}
end

function Pipeline:apply(datatensor, can_fit)
   for i, item in ipairs(self._items) do
      item:apply(datatensor, can_fit)
   end
end

-----------------------------------------------------------------------
-- Binarize : A Preprocessor that set to 0 any pixel strictly below the 
---threshold, sets to 1 those above or equal to the threshold.
-----------------------------------------------------------------------
local Binarize = torch.class("dp.Binarize", "dp.Preprocess")
Binarize.isBinarize = true

function Binarize:__init(threshold)
   self._threshold = threshold
end

function Binarize:apply(datatensor)
   local data = datatensor:data()
   inputs[data:lt(self._threshold)] = 0;
   inputs[data:ge(self._threshold)] = 1;
   datatensor:setData(data)
end

-----------------------------------------------------------------------
-- Standardize : A Preprocessor that subtracts the mean and divides 
-- by the standard deviation.
-----------------------------------------------------------------------
local Standardize = torch.class("dp.Standardize", "dp.Preprocess")
Standardize.isStandardize = true

function Standardize:__init(...)
   local args
   args, self._global_mean, self._global_std, self._std_eps
      = xlua.unpack(
      {... or {}},
      'Standardize', nil,
      {arg='global_mean', type='boolean', 
       help=[[If true, subtract the (scalar) mean over every element
            in the dataset. If false, subtract the mean from
            each column (feature) separately.
            ]], default=false},
      {arg='global_std', type='boolean', 
       help=[[If true, after centering, divide by the (scalar) standard
            deviation of every element in the design matrix. If false,
            divide by the column-wise (per-feature) standard deviation.
            ]], default=false},
      {arg='std_eps', type='number', 
       help=[[Stabilization factor added to the standard deviations before
            dividing, to prevent standard deviations very close to zero
            from causing the feature values to blow up too much.
            ]], default=1e-4}
   )
end

function Standardize:apply(datatensor, can_fit)
   local data = datatensor:feature()
   if can_fit then
      self._mean = self._global_mean and data:mean() or data:mean(1)
      self._std = self._global_std and data:std() or data:std(1)
   elseif self._mean == nil or self._std == nil then
          error([[can_fit is false, but Standardize object
                  has no stored mean or standard deviation]])
   end
   if self._global_mean then
      data:add(-self._mean)
   else
      -- broadcast
      data:add(-self._mean:expandAs(data))
   end
   if self._global_std then
      data:cdiv(self._std + self._std_eps)
   else
      data:cdiv(self._std:expandAs(data) + self._std_eps)
   end
   datatensor:setData(data)
end

-----------------------------------------------------------------------
-- GCN : Global contrast normalizes by (optionally) 
-- subtracting the mean across features and then normalizes by either the 
-- vector norm or the standard deviation (across features, for each example).
-----------------------------------------------------------------------
local GCN, parent = torch.class("dp.GCN", "dp.Preprocess")
GCN.isGCN = true

function GCN:__init(...)
   local args
   args, self._subtract_mean, self._scale, self._sqrt_bias, 
   self._use_std, self._min_divisor, self._std_bias, self._batch_size, 
   self._use_norm
      = xlua.unpack(
      {... or {}},
      'GCN', nil,
      {arg='subtract_mean', type='boolean', default=true, 
       help='when True subtract the mean of each example.'},
      {arg='scale', type='number', default=55, 
       help='Multiply features by this const.'},
      {arg='sqrt_bias', type='number', default=0,
       help='Fudge factor added inside the square root.'},
      {arg='use_std', type='boolean', default=false, 
       help='If True uses the norm instead of the standard deviation.'},
      {arg='min_divisor', type='number', default=1e-8,
       help='If the divisor for an example is less than this value, '..
       'do not apply it.'},
      {arg='std_bias', type='number', default=0,
       help='Add this amount inside the square root when computing '..
       'the standard deviation or the norm'},
      {arg='batch_size', type='number', default=0, 
       help='The size of a batch.'},
      {arg='use_norm', type='boolean', default=false,
       help='Normalize the data'}
   )
end
    
function GCN:apply(datatensor, can_fit)
   local data = datatensor:feature()
   print('begin Global Contrast Normalization Preprocessing...')
   if self._batch_size == 0 then
      self:_transform(data)
   else
      local data_size = data:size(1)
      local last = math.floor(data_size / self._batch_size) * self._batch_size

      for i = 0, data_size, self._batch_size do
         if i >= last then
            stop = i + math.mod(data_size, self._batch_size)
         else
            stop = i + self._batch_size
         end
         self:_transform(data:sub(i,stop))
      end
   end
   print('Global Contrast Normalization Preprocessing completed')
end

function GCN:_transform(data)
	if self._subtract_mean then
		data:add(-data:mean(2):expandAs(data))
	end
	
	local scale
	if self._use_norm then
		scale = torch.sqrt(data:pow(2):sum(2):add(self._std_bias))
	else
		scale = torch.sqrt(data:pow(2):mean(2):add(self._std_bias))
	end
	
	local eps = 1e-8
	scale[torch.lt(scale, eps)] = 1
	data:cdiv(scale:expandAs(data)):mul(self._scale)
end

-----------------------------------------------------------------------
--[[ ZCA ]]--
-- Performs ZCA Whitening
-----------------------------------------------------------------------
local ZCA = torch.class("dp.ZCA", "dp.Preprocess")
ZCA.isZCA = true

function ZCA:__init(...)
   local args
   args, self.n_components, self.n_drop_components, self._filter_bias
      = xlua.unpack(
      {... or {}},
      'ZCA', 'ZCA whitening constructor',
      {arg='n_component', type='number',
       help='number of most important eigen components to use for ZCA'},
      {arg='n_drop_component', type='number', 
       help='number of least important eigen components to drop.'},
      {arg='filter_bias', type='number', default=0.1}
   )
end

function ZCA:fit(X)
   assert (X:dim() == 2)
   local n_samples = X:size()[1]
         
   -- center data
   self._mean = X:mean(1)
   X:add(-self._mean:expandAs(X))

   print'computing ZCA'
   local matrix = torch.mm(X:t(), X) / X:size(1)
   matrix:add(torch.eye(matrix:size(1)):mul(self._filter_bias)) 
   -- returns a eigen components in ascending order of importance
   local eig_val, eig_vec = torch.eig(matrix, 'V')
   local eig_val = eig_val:select(2,1)
   print'done computing eigen values and vectors'
   assert(eig_val:min() > 0)
   if self.n_components then
     eig_val = eig_val:sub(1, self.n_components)
     eig_vec = eig_vec:narrow(2, 1, self.n_components)
   end
   if self.n_drop_components then
      eig_val = eig_val:sub(self.n_drop_component, -1)
      local size = eig_vec:size(2)-self.n_drop_component
      eig_vec = eig_vec:narrow(2, self.n_drop_component, size)
   end
   self._P = torch.mm(
      torch.cmul(eig_vec, eig_val:pow(-0.5):reshape(1, eig_val:size(1)):expandAs(eig_vec)), 
      eig_vec:t()
   )
   assert(not _.isNaN(self._P:sum()))
end

function ZCA:apply(datatensor, can_fit)
   local X = datatensor:feature()
   local new_X
   if can_fit then
      self:fit(X)
      new_X = torch.mm(X, self._P)
   else
      new_X = torch.mm(torch.add(X, -self._mean:expandAs(X)), self._P)
   end
   datatensor:setData(new_X)
end

-----------------------------------------------------------------------
--[[ LeCunLCN ]]--
-- Performs Local Contrast Normalization
-----------------------------------------------------------------------
local LeCunLCN = torch.class("dp.LeCunLCN", "dp.Preprocess")
LeCunLCN.isLeCunLCN = true

function LeCunLCN:__init(...)
   local args
   args, self._kernel_size, self._threshold = xlua.unpack(
      {... or {}},
      'LeCunLCN', 'LeCunLCN constructor',
      {arg='kernel_size', type='number', 
       help=[[local contrast kernel size]], default=9},
      {arg='threshold', type='number',
       help=[[threshold for denominator]], default=1e-4}
   )     
end

function LeCunLCN:_gaussian_filter(kernel_size)
   local x = torch.zeros(kernel_size, kernel_size)
   local _gauss = function(x, y, sigma)
      sigma = sigma or 2.0
      local Z = 2 * math.pi * math.pow(sigma, 2)
      return 1 / Z * math.exp(-(math.pow(x,2)+math.pow(y,2))/(2 * math.pow(sigma,2)))
   end
   
   local mid = math.ceil(kernel_size / 2)
   for i = 1, kernel_size do
      for j = 1, kernel_size do
         x[i][j] = _gauss(i-mid, j-mid)
      end
   end
   
   return x / x:sum()
end

function LeCunLCN:apply(datatensor, can_fit)

   print ('Start LeCunLCN Preprocessing ... ')
   
   local data, axes = datatensor:image()
   assert(table.eq(axes, {'b', 'h', 'w', 'c'}), 'data axes is not equal to {b ,h, w, c}')
          
   local filters = self:_gaussian_filter(self._kernel_size)
   print('start convolving data')
   local convout = dp.conv2d(data, filters, {'b','h','w','c'}, {'h', 'w'})
   print('1/3 finished convolving data, start convolving centered_X ...')
   local mid = math.ceil(self._kernel_size / 2)
   local centered_X = data - convout[{{1, -1},{mid, -mid},{mid, -mid},{1, -1}}]
   local sum_sqr_XX = dp.conv2d(torch.pow(centered_X,2), filters, 
                                {'b', 'h', 'w', 'c'}, {'h', 'w'})
   print('2/3 finished convolving centered_X, start finding divisor ...')
   local denom = torch.sqrt(sum_sqr_XX[{{1,-1},{mid, -mid},{mid, -mid},{1, -1}}])
   local resized = denom:resize(denom:size(1), denom:size(2) * denom:size(3), denom:size(4))
   local per_img_mean = torch.mean(resized, 2)
   per_img_mean:resize(per_img_mean:size(1), 1, 1, per_img_mean:size(3))
   local expanded = per_img_mean:expandAs(data)
   denom:resize(data:size(_.indexOf(axes, 'b')), data:size(_.indexOf(axes, 'h')),
                data:size(_.indexOf(axes, 'w')), data:size(_.indexOf(axes, 'c')))
   local divisor = denom:map(expanded, function(d, e) return d>e and d or e end)
   print('3/3 finished finding divisor, finishing preprocessing ..')
   divisor = divisor:apply(function(x) return x>self._threshold and x or self._threshold end)
   print ('LeCunLCN Preprocessing completed')
   local new_X = centered_X:cdiv(divisor)
   datatensor:setData(new_X)
end
   
