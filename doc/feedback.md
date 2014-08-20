# Give me some Feedback  #
Feedback objects are used to provide I/O feedback to other objects or users. This inclues performance measures and 
statistics which can be used for early-stopping (cross-validation) or used to guide training. Currently, the following Feeback classes are supported:
 * [Feedback](#dp.Model) : abstract class;
   * [Confusion](#dp.Confusion) : adapts the optim ConfusionMatrix (used for classification);
   * [Perplexity](#dp.Perplexity) : measures perplexity (used for language models);
   * [FacialKeypointFeedback](#dp.FacialKeypointFeedback) : measures the MSE for facial keypoint detection;
   * [CompositeFeedback](#dp.CompositeFeedback) : composite of Feedback components ;

<a name="dp.Feedback"/>
## Feedback ##
Abstract class. Strategy (design pattern) for processing predictions and targets. 
Unlike [Observers](observer.md), Feedback objects generate reports. 
Like Observers they may also publish/subscribe to mediator channels.

### dp.Feedback{name} ###
Feedback constructor. Only accepts key-value arguments:
 * `name` is a string used to identify the reports generated by this object. Usually hard-coded in sub-class.
 
### setup{mediator, propagator, dataset} ###
Post-initialization method for mediation and such:
 * `mediator` is a [Mediator](mediator.md#dp.Mediator) used for inter-object communication.
 * `propagator` is the [Propagator](propagator.md#dp.Propagator) which this object extends.
 * `dataset` is a [DataSet](data.md#dp.DataSet). This might be useful to determine the type of targets. Feedback should not hold a reference to the dataset due to it's possible serialization.

### add(batch, output, carry, report) ###
The main method of the object. It is called for every `batch` propagated through the [Model](model.md#dp.Model).
 * `batch` is the current [Batch](data.md#dp.Batch) being propagated by the subject Propagator.
 * `output` is the forward propagated output [View](view.md#dp.View) of the model.
 * `carry` is the propagated table of meta-data. It can be modified to pass on information to Models during the backward pass;
 *`report` is a table of statistics and meta-data returned by the [Experiment:report](experiment.md#dp.Experiment.report) method during the last epoch;

<a name="dp.Confusion"/>
## Confusion ##
Confusion is a wrapper for the [ConfusionMatrix](https://github.com/torch/optim/blob/master/ConfusionMatrix.lua) found in the [optim](https://github.com/torch/optim/blob/master/README.md) package.

<a name="dp.Perplexity"/>
## Perplexity ##
Computes perplexity for language models. For now, only works with the SoftmaxTree Model.

<a name="dp.FacialKeypointFeedback"/>
## FacialKeypointFeedback ##
Measures MSE with respect to targets and optionaly compares this to constant (mean) value baseline.

<a name="dp.CompositeFeedback"/>
## CompositeFeedback ##
Composite of Feedback components.