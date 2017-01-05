create or replace procedure promise_job_notify_run (
  event_message           promise_job_notify
)

as

  l_dequeue_options     dbms_aq.dequeue_options_t;
  l_message_properties  dbms_aq.message_properties_t;
  l_first_dequeue       boolean := true;
  l_message_handle      raw(16);
  l_promise_result      promise_result;

  -- Exceptions
  l_exception_timeout   exception;
  pragma exception_init(l_exception_timeout, -25228);

begin

  -- We have a promise complete. Check for triggers.
  loop

    l_dequeue_options.dequeue_mode := dbms_aq.browse;
    l_dequeue_options.wait := dbms_aq.no_wait;
    l_dequeue_options.visibility := dbms_aq.immediate;
    if l_first_dequeue then
      l_dequeue_options.navigation := dbms_aq.first_message;
    else
      l_dequeue_options.navigation := dbms_aq.next_message;
    end if;

    -- First dequeue. Only browse
    dbms_aq.dequeue(
      queue_name              =>    'promise_async_queue'
      , dequeue_options       =>    l_dequeue_options
      , message_properties    =>    l_message_properties
      , payload               =>    l_promise_result
      , msgid                 =>    l_message_handle
    );

    if l_first_dequeue then
      l_first_dequeue := false;
    end if;

    if l_promise_result.thenable_status = event_message.promise_name then
      -- We should dequeue for remove, and execute thenable as job.
      -- Dequeue directly using the msgid.
      l_dequeue_options.dequeue_mode := dbms_aq.remove;
      l_dequeue_options.wait := dbms_aq.no_wait;
      l_dequeue_options.visibility := dbms_aq.immediate;
      l_dequeue_options.msgid := l_message_handle;
      -- Dequeue for remove.
      dbms_aq.dequeue(
        queue_name              =>    'promise_async_queue'
        , dequeue_options       =>    l_dequeue_options
        , message_properties    =>    l_message_properties
        , payload               =>    l_promise_result
        , msgid                 =>    l_message_handle
      );
      -- Schedule thenable for immediate execution.
      dbms_scheduler.create_job (
        job_name              =>      l_promise_result.promise_name || '_J'
        , job_type            =>      'PLSQL_BLOCK'
        , job_action          =>      l_promise_result.thenable
        , enabled             =>      true
      );
    end if;

  end loop;

  exception
    when l_exception_timeout then
      null;

end promise_job_notify_run;
/
