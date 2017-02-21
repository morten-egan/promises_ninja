create or replace package promises_ninja

as

  /** Package implementing PLSQL equivalent of Javascript promises (https://promisesaplus.com/)
  * @author Morten Egan
  * @version 0.0.1
  * @project promises_ninja
  */
  npg_version         varchar2(250) := '0.0.1';

  promise_lifetime    number := 604800;

  -- type to build list of promises. Used in combination with all and race methods.
  type promise_list_type is table of promise;

  /** This procedure adds a promise to a list of promises.
  * @author Morten Egan
  * @param promise_list The list of promises we are working on.
  * @param add_promise The promise we are adding to the list.
  */
  procedure build_promise_list (
    promise_list              in out        promise_list_type
    , add_promise             in            promise
  );

  /** This function will take a promise list as input and dynamically create an anydataset, convert to
  * anydata which can be treated as an input variable for a new promise.
  * @author Morten Egan
  * @param promise_list The list of promises to convert for input to a new promise.all call.
  * @return sys.anydataset The anydataset object holding the anydataset which is a list of promises.
  */
  function convert_promise_list (
    promise_list              in            promise_list_type
  )
  return sys.anydata;

  /** This function will take a promise from an all call, and convert the anydata result to
  * a list of promises that can be accessed directly.
  * @author Morten Egan
  * @return promise_list_type The list of promises that is returned. Will return null if not resolved.
  */
  function getvalues_promise_list (
    ref_promise               in            promise
  )
  return promise_list_type;

  /** This procedure will wait for a promise to complete.
  * @author Morten Egan
  * @param ref_promise This is the promise that we will wait for completion.
  * @param sleeptime The amount of time to sleep between iterations of getting result.
  */
  procedure promise_wait (
    ref_promise             in out nocopy   promise
    , sleeptime             in              number      default 3
  );

  /** Procedure to cancel promises. Stops everything that is running.
  * Removes all messages and finally nullifies the actual promise.
  * @author Morten Egan
  * @param ref_promise This is the promise that will get cancelled.
  */
  procedure promise_cancel (
    ref_promise             in out nocopy   promise
  );

  /** Procedure to get runtime status of promise.
  * @author Morten Egan
  * @param ref_promise The promise that we are getting status on.
  */
  procedure promise_status (
    ref_promise             in out nocopy   promise
    , promise_state         out             varchar2
    , chained               out             boolean
    , on_chain_step         out             number
    , total_chain_steps     out             number
    , next_promise          out             varchar2
    , previous_promise      out             varchar2
  );

end promises_ninja;
/
