create type promise as object (

  /*
  * Variables/Attributes
  */
  -- promise_name is the internal name of the promise.
  promise_name              varchar2(128)
  -- state of the promise. pending, fulfilled, rejected.
  , state                   varchar2(20)
  -- state_time is the time that the state was set. Used especially for race calls where the first result is the final result.
  , state_time              date
  -- chain_size is a count of how many then_p calls that has been called on this promise. Used to determine call order.
  , chain_size              number
  -- All flag. If this flag is set we treat the promise a little bit specially since we are waiting for multiple promises.
  , all_flag                number
  -- Race flag. If this flag is set we treat this promise as a race between the promises it will be initiated with.
  , race_flag               number
  -- val is the value of the promise result when the promise is fullfilled.
  , val                     sys.anydata
  -- typeval is a numeric representation of the value type.
  --   Standard type: 0=null, 1=number, 2=varchar2, 3=clob, 4=date, 5=blob
  --   Special types: 84=List of values, result from all call. Represented as anydata of p_datalist_o.
  , typeval                 number
  -- o_executor is the name of the function that we are calling.
  , o_executor              varchar2(30)
  -- o_executor_val is the input value to o_executor
  , o_executor_val          sys.anydata
  -- o_executer_typeval is the input value type.
  --   Standard type: 0=null, 1=number, 2=varchar2, 3=clob, 4=date, 5=blob
  --   Special types: 42=List of promises. Represented as anydata of p_datalist_o.
  , o_executor_typeval      number
  -- o_execute
  , o_execute               number
  -- Promise class. Use this class as the job class when running the promises.
  -- This is to support Job classes in dbms_scheduler so jobs can run using the
  -- correct service and edition.
  , promise_class           varchar2(32)
  /*
  * Constructors
  */
  -- Empty
  , constructor function promise return self as result
  -- Executor with onfullfilled and onrejected but no input to
  , constructor function promise (executor varchar2, promise_class varchar2 default null) return self as result
  -- Executor with onfullfilled and parameter for executor.
  , constructor function promise (executor varchar2, executor_val number, promise_class varchar2 default null) return self as result
  , constructor function promise (executor varchar2, executor_val varchar2, promise_class varchar2 default null) return self as result
  , constructor function promise (executor varchar2, executor_val date, promise_class varchar2 default null) return self as result

  /*
  * Methods
  */
  -- validate, where we validate all the settings so far. If anything is wrong, we set to failed.
  , member procedure validate_p (self in out nocopy promise)
  -- done.
  , member procedure then_p (self in out promise, ref_promise in out promise, on_fullfilled varchar2 default null, on_rejected varchar2 default null)
  -- then, where we actually care about the result. Return is the pointer to the data. Callers responsibility to check if completed.
  , member function then_f (self in out promise, on_fullfilled varchar2 default null, on_rejected varchar2 default null) return promise
  -- all, where we take a list of promises and only when all promises are fulfilled we consider fulfilled.
  , member procedure all_p (self in out promise, promise_list sys.anydata, on_fullfilled varchar2 default null, on_rejected varchar2 default null)
  -- race, where we take a list of promises and whenever the first promise is resolved, that becomes the result.
  , member procedure race_p (self in out promise, promise_list sys.anydata, on_fullfilled varchar2 default null, on_rejected varchar2 default null)
  -- Catch, should be used as the last call in a chain to make sure you catch any potential errors from the last wanted step.
  , member function catch (self in out promise, on_rejected varchar2) return promise
  -- Generate and return a uniqueue promise name.
  , member function get_promise_name return varchar2
  -- Procedure to execute the promise, if not a thenable.
  , member procedure execute_promise(self in out nocopy promise)
  -- Check queue for return value.
  , member procedure check_and_set_value(self in out promise)
  -- Send message to result queue.
  , member procedure result_enqueue(self in out promise, queue_name varchar2, queue_message promise_result)
  -- Send message to job queue.
  , member procedure job_enqueue(self in out promise, queue_name varchar2, queue_message promise_job_notify)
  -- Resolve procedures
  , member procedure resolve(self in out promise, resolved_val promise, all_idx number default null)
  , member procedure resolve(self in out promise, resolved_val number, all_idx number default null)
  , member procedure resolve(self in out promise, resolved_val varchar2, all_idx number default null)
  , member procedure resolve(self in out promise, resolved_val date, all_idx number default null)
  -- Reject procedure
  , member procedure reject(self in out promise, rejection varchar2, all_idx number default null)

  /*
  * Getters
  */
  -- Get the current value of the promise. If succeeded, then set status as fulfilled and set value.
  , member function getvalue(self in out promise) return sys.anydata
  -- datatype specific getters.
  , member function getvalue_number(self in out promise) return number
  , member function getvalue_varchar(self in out promise) return varchar2
  , member function getvalue_date(self in out promise) return date
  -- Generic getter for all types
  , member function getanyvalue(self in out promise) return varchar2

  /*
  * Helper utilities
  */
  , member function on_is_function(function_name varchar2) return boolean
  , member function get_exec_job_code return varchar2
  , member function get_then_job_code(on_fullfilled varchar2, on_rejected varchar2, new_promise_name varchar2) return varchar2
  , member function get_function_return(function_name varchar2) return number
)
not final;
/
