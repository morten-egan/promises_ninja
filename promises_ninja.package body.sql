create or replace package body promises_ninja

as

  procedure promise_wait (
    ref_promise             in out nocopy   promise
    , sleeptime             in              number      default 3
  )

  as

    l_is_pending            boolean := true;

  begin

    dbms_application_info.set_action('promise_wait');

    while l_is_pending loop
      ref_promise.check_and_set_value;
      if ref_promise.state != 'pending' then
        exit;
      end if;
      dbms_lock.sleep(sleeptime);
    end loop;

    dbms_application_info.set_action(null);

    exception
      when others then
        dbms_application_info.set_action(null);
        raise;

  end promise_wait;

  procedure promise_cancel (
    ref_promise             in out nocopy   promise
  )

  as

    l_promise_result      promise_result;
    l_dequeue_options     dbms_aq.dequeue_options_t;
    l_message_properties  dbms_aq.message_properties_t;
    l_message_handle      raw(16);

    cursor getting_chain(p_name varchar2) is
      select
        *
      from
        (
          select
            msgid
            , treat(user_data as promise_result).promise_name as promise_name
            , treat(user_data as promise_result).promise_result as promise_result
            , treat(user_data as promise_result).promise_typeval as promise_typeval
            , treat(user_data as promise_result).thenable_status as thenable_status
            , treat(user_data as promise_result).thenable_order as thenable_order
            , treat(user_data as promise_result).thenable as thenable
          from
            promise_async_tab
        ) pat
      start with pat.promise_name = p_name
      connect by prior pat.promise_name = pat.thenable_status;


  begin

    dbms_application_info.set_action('promise_cancel');

    -- If not pending, we do not cancel jobs. Because we're already done with it.
    if ref_promise.state = 'pending' then
      -- First let us make sure the job of the current promise is stopped and dropped.
      begin
        dbms_scheduler.stop_job(ref_promise.promise_name || '_J');
      exception
        when others then
          null;
      end;
      -- Next we drop that job.
      begin
        dbms_scheduler.drop_job(ref_promise.promise_name || '_J');
      exception
        when others then
          null;
      end;
    end if;

    -- Next we need to do a connect by lookup of chained promises.
    -- then remove the messages from the queue.
    for msg in getting_chain(ref_promise.promise_name) loop
      -- Wrap it in an exception block, so if cancel fails, outer block does not fail.
      begin
        l_dequeue_options.dequeue_mode := dbms_aq.remove;
        l_dequeue_options.wait := dbms_aq.no_wait;
        l_dequeue_options.visibility := dbms_aq.immediate;
        l_dequeue_options.msgid := msg.msgid;
        dbms_aq.dequeue(
          queue_name              =>    'promise_async_queue'
          , dequeue_options       =>    l_dequeue_options
          , message_properties    =>    l_message_properties
          , payload               =>    l_promise_result
          , msgid                 =>    l_message_handle
        );
      exception
        when others then
          null;
      end;
    end loop;

    -- Now all dependent objects should be removed.
    -- Set the promise itself to null.
    ref_promise := null;

    dbms_application_info.set_action(null);

    exception
      when others then
        dbms_application_info.set_action(null);
        raise;

  end promise_cancel;

  procedure promise_status (
    ref_promise             in out nocopy   promise
    , promise_state         out             varchar2
    , chained               out             boolean
    , on_chain_step         out             number
    , total_chain_steps     out             number
    , next_promise          out             varchar2
    , previous_promise      out             varchar2
  )

  as

    l_total_chain_count         number := null;
    l_upstream_chain_count      number := 0;
    l_downstream_chain_count    number := 0;

    -- Moving down from current promise in chain.
    cursor move_down_chain(p_name varchar2) is
      select
          level
          , pat.*
          , count(pat.promise_name) over (order by thenable) as all_count
        from
          (
            select
              msgid
              , treat(user_data as promise_result).promise_name as promise_name
              , treat(user_data as promise_result).promise_result as promise_result
              , treat(user_data as promise_result).promise_typeval as promise_typeval
              , treat(user_data as promise_result).thenable_status as thenable_status
              , treat(user_data as promise_result).thenable_order as thenable_order
              , treat(user_data as promise_result).thenable as thenable
            from
              promise_async_tab
          ) pat
        start with pat.promise_name = p_name
        connect by prior pat.promise_name = pat.thenable_status;
    -- Moving up from current promise in chain.
    cursor move_up_chain(p_name varchar2) is
      select
          level
          , pat.*
          , count(pat.promise_name) over (order by thenable) as all_count
        from
          (
            select
              msgid
              , treat(user_data as promise_result).promise_name as promise_name
              , treat(user_data as promise_result).promise_result as promise_result
              , treat(user_data as promise_result).promise_typeval as promise_typeval
              , treat(user_data as promise_result).thenable_status as thenable_status
              , treat(user_data as promise_result).thenable_order as thenable_order
              , treat(user_data as promise_result).thenable as thenable
            from
              promise_async_tab
          ) pat
        start with pat.promise_name = p_name
        connect by prior pat.thenable_status = pat.promise_name;

  begin

    dbms_application_info.set_action('promise_status');

    ref_promise.check_and_set_value;

    promise_state := ref_promise.state;

    -- Set defaults
    chained := false;
    on_chain_step := null;
    total_chain_steps := null;
    next_promise := null;
    previous_promise := null;

    if ref_promise.chain_size > 0 then
      chained := true;
      -- Let us set the chained data.
      for upromises in move_up_chain(ref_promise.promise_name) loop
        l_upstream_chain_count := upromises.all_count - 1;
        if upromises.level = 2 then
          -- Previous chain step.
          previous_promise := upromises.promise_name;
        end if;
      end loop;
      for dpromises in move_down_chain(ref_promise.promise_name) loop
        l_downstream_chain_count := dpromises.all_count - 1;
        if dpromises.level = 2 then
          -- Previous chain step.
          next_promise := dpromises.promise_name;
        end if;
      end loop;
      total_chain_steps := l_upstream_chain_count + 1 + l_downstream_chain_count;
      on_chain_step := l_upstream_chain_count + 1;
    end if;

    dbms_application_info.set_action(null);

    exception
      when others then
        dbms_application_info.set_action(null);
        raise;

  end promise_status;

  procedure build_promise_list (
    promise_list              in out        promise_list_type
    , add_promise             in            promise
  )

  as

  begin

    dbms_application_info.set_action('build_promise_list');

    if promise_list is null then
      promise_list := promise_list_type();
    end if;

    promise_list.extend(1);
    promise_list(promise_list.count) := add_promise;

    dbms_application_info.set_action(null);

    exception
      when others then
        dbms_application_info.set_action(null);
        raise;

  end build_promise_list;

  function convert_promise_list (
    promise_list              in            promise_list_type
  )
  return sys.anydata

  as

    l_ret_var               sys.anydata;
    l_tmp_obj               promises_list_obj;

  begin

    dbms_application_info.set_action('convert_promise_list');

    l_tmp_obj.promise_list := promise_list_tab();

    for i in 1..convert_promise_list.promise_list.count() loop
      l_tmp_obj.promise_list.extend(1);
      l_tmp_obj.promise_list(l_tmp_obj.promise_list.count()) := sys.anydata.convertObject(convert_promise_list.promise_list(i));
    end loop;

    l_ret_var := sys.anydata.convertObject(l_tmp_obj);

    dbms_application_info.set_action(null);

    return l_ret_var;

    exception
      when others then
        dbms_application_info.set_action(null);
        raise;

  end convert_promise_list;

  function getvalues_promise_list (
    ref_promise               in            promise
  )
  return promise_list_type

  as

    l_ret_var               promise_list_type := promise_list_type();
    l_tmp_obj               promises_list_obj;
    l_tmp_tab               promise_list_tab;
    l_tmp_promise           promise;

  begin

    dbms_application_info.set_action('getvalues_promise_list');

    if ref_promise.state = 'fulfilled' then
      -- l_tmp_obj := sys.anydata.convertObject(ref_promise.val);
      if ref_promise.val.getObject(l_tmp_obj) = dbms_types.success then
        l_tmp_tab := l_tmp_obj.promise_list;
        for i in 1..l_tmp_tab.count() loop
          l_ret_var.extend(1);
          if l_tmp_tab(i).getObject(l_tmp_promise) = dbms_types.success then
            l_ret_var(l_ret_var.count()) := l_tmp_promise;
          else
            l_ret_var(l_ret_var.count()) := null;
          end if;
        end loop;
      else
        l_ret_var := null;
      end if;
    else
      l_ret_var := null;
    end if;

    dbms_application_info.set_action(null);

    return l_ret_var;

    exception
      when others then
        dbms_application_info.set_action(null);
        raise;

  end getvalues_promise_list;

begin

  dbms_application_info.set_client_info('promises_ninja');
  dbms_session.set_identifier('promises_ninja');

end promises_ninja;
/
