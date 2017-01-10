create or replace package promises_ninja

as

  /** Package implementing PLSQL equivalent of Javascript promises (https://promisesaplus.com/)
  * @author Morten Egan
  * @version 0.0.1
  * @project promises_ninja
  */
  npg_version         varchar2(250) := '0.0.1';

  promise_lifetime    number := 604800;

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
