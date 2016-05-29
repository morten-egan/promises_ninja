create or replace package promises_ninja

as

  /** Package implementing PLSQL equivalent of Javascript promises (https://promisesaplus.com/)
  * @author Morten Egan
  * @version 0.0.1
  * @project promises_ninja
  */
  npg_version         varchar2(250) := 0.0.1;

  type promise_o is object (
    aa23        varchar2(20)
  )

  /** The promise function returning an active promise
  * @author Morten Egan
  * @return promise_o The promise object.
  */
  function promise (

  )
  return promise_o;

end promises_ninja;
/
