begin

  dbms_scheduler.create_program (
    program_name            =>    'PROMISE_NOTIFY_PRG'
    , program_type          =>    'STORED_PROCEDURE'
    , program_action        =>    'PROMISE_JOB_NOTIFY_RUN'
    , number_of_arguments   =>    1
  );

  dbms_scheduler.define_metadata_argument (
    program_name            =>    'PROMISE_NOTIFY_PRG'
    , metadata_attribute    =>    'event_message'
    , argument_position     =>    1
  );

  dbms_scheduler.enable('PROMISE_NOTIFY_PRG');

  dbms_scheduler.create_job(
    job_name                =>    'PROMISE_NOTIFY_J'
    , program_name          =>    'PROMISE_NOTIFY_PRG'
    , start_date            =>    systimestamp
    , event_condition       =>    null -- Catch all event messages.
    , queue_spec            =>    'promise_job_queue'
    , enabled               =>    true
  );

end;
/
