create or replace type body promise as

  constructor function promise
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := null;
    self.o_execute := 0;

    return;

  end promise;

  constructor function promise (
    executor            varchar2
  )
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := executor;
    self.o_executor_typeval := 0;
    self.o_execute := 0;

    self.validate_p();

    self.execute_promise();

    return;

  end promise;

  constructor function promise (
    executor            varchar2
    , executor_val      number
  )
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := executor;
    self.o_executor_typeval := 1;
    self.o_executor_val := sys.anydata.convertnumber(executor_val);
    self.o_execute := 0;

    self.validate_p();

    self.execute_promise();

    return;

  end promise;

  constructor function promise (
    executor            varchar2
    , executor_val      varchar2
  )
  return self as result

  as

  begin

    self.promise_name := self.get_promise_name();
    self.state := 'pending';
    self.typeval := 0;
    self.o_executor := executor;
    self.o_executor_typeval := 2;
    self.o_executor_val := sys.anydata.convertvarchar2(executor_val);
    self.o_execute := 0;

    self.validate_p();

    self.execute_promise();

    return;

  end promise;

  member procedure validate_p (
    self                in out nocopy        promise
  )

  as

    l_function_exists       number;
    l_function_input        all_arguments%rowtype;
    l_function_output       all_arguments%rowtype;

  begin

    if self.o_executor != 'E_PROMISE' then
      -- We have a normal function as executor. Check that it exists.
      select count(*)
      into l_function_exists
      from all_objects
      where object_name = upper(self.o_executor)
      and object_type = 'FUNCTION';
      if l_function_exists > 0 then
        -- Function exists
        -- Check input type, if called with input val.
        if self.o_executor_typeval > 0 then
          begin
            select *
            into l_function_input
            from all_arguments
            where object_name = upper(self.o_executor)
            and in_out = 'IN'
            and position = 1;
            if l_function_input.data_type = 'NUMBER' and self.o_executor_typeval != 1 then
              raise_application_error(-20042, 'promise executor, input parameter mismatch');
            elsif l_function_input.data_type = 'VARCHAR2' and self.o_executor_typeval != 2 then
              raise_application_error(-20042, 'promise executor, input parameter mismatch');
            end if;
            exception
              when others then
                raise_application_error(-20042, 'promise executor, input parameter mismatch');
          end;
        end if;
        -- Check and set the output type.
        select *
        into l_function_output
        from all_arguments
        where object_name = upper(self.o_executor)
        and in_out = 'OUT';
        if l_function_output.data_type = 'NUMBER' then
          self.typeval := 1;
        elsif l_function_output.data_type = 'VARCHAR2' then
          self.typeval := 2;
        else
          raise_application_error(-20042, 'only number or varchar2 output currently supported for promises');
        end if;
      else
        raise_application_error(-20042, 'promise executor invalid privileges or does not exist');
      end if;
    else
      -- We have a promise. Add self to chain with correct dependencies.
      null;
    end if;

    -- We have reached the end of the validation procedure.
    -- Enable execution of promise.
    self.o_execute := 1;

  end validate_p;

  member function get_promise_name
  return varchar2

  as

  begin

    return 'P_' || substr(sys_guid(), 1, 26);

  end get_promise_name;

  member procedure done_p (
    on_fullfilled                       varchar2    default null
    , on_rejected                       varchar2    default null
  )

  as

  begin

    -- First check if promise has been validated.
    -- Do not allow an promise that has not been validated to be executed.
    if self.o_execute > 0 then
      null;
    else
      raise_application_error(-20042, 'cannot call done on promise that is not validated');
    end if;

  end done_p;

  member function then_p (
    on_fullfilled                     varchar2      default null
    , on_rejected                     varchar2      default null
  )
  return promise

  as

    new_promise         promise;

  begin

    -- First check if promise has been validated.
    -- Do not allow an promise that has not been validated to be executed.
    if self.o_execute > 0 then

      -- Initiate the new promise that we will return.
      new_promise := promise();

      if self.state = 'fulfilled' then
        -- We already have the final result of the promise.
        -- Just add to chain.
        null;
      elsif self.state = 'rejected' then
        -- Check if on rejected is set, and existing rejected chain is there.
        null;
      else
        -- We are in pending. Just attach to existing chain.
        -- Attach on_fullfilled if defined to success chain.
        -- Attach on_rejected if defined to failure chain.
        null;
      end if;

      return new_promise;
    else
      raise_application_error(-20042, 'cannot call then on promise that is not validated');
    end if;

  end then_p;

  member procedure execute_promise(
    self in out nocopy promise
  )

  as

    l_anonymous_plsql_block       varchar2(32000);

  begin

    l_anonymous_plsql_block := 'declare
      l_full_error          varchar2(4000);
      l_enqueue_options     dbms_aq.enqueue_options_t;
      l_message_properties  dbms_aq.message_properties_t;
      l_message_recipients  dbms_aq.aq$_recipient_list_t;
      l_message_handle      raw(16);
      l_queue_message       promise_result;
      l_promise_result      ';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'number;';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000);';
    end if;
    if self.o_executor_typeval > 0 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '
      l_executor_var        ';
      if self.o_executor_typeval = 1 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'number := ' || to_char(sys.anydata.accessNumber(self.o_executor_val)) || ';';
      elsif self.o_executor_typeval = 2 then
        l_anonymous_plsql_block := l_anonymous_plsql_block || 'varchar2(32000) := ''' || to_char(sys.anydata.accessVarchar2(self.o_executor_val)) || ''';';
      end if;
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
      begin
        l_promise_result := ';
    if self.o_executor_typeval > 0 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || self.o_executor || '(l_executor_var);';
    else
      l_anonymous_plsql_block := l_anonymous_plsql_block || self.o_executor || ';';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
      l_queue_message := promise_result';
    if self.typeval = 1 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '(''' || self.promise_name || ''', ''SUCCESS'', 1, sys.anydata.convertnumber(l_promise_result));';
    elsif self.typeval = 2 then
      l_anonymous_plsql_block := l_anonymous_plsql_block || '(''' || self.promise_name || ''', ''SUCCESS'', 2, sys.anydata.convertvarchar2(l_promise_result));';
    end if;
    l_anonymous_plsql_block := l_anonymous_plsql_block || '
      dbms_aq.enqueue(
        queue_name            =>    ''promise_async_queue''
        , enqueue_options     =>    l_enqueue_options
        , message_properties  =>    l_message_properties
        , payload             =>    l_queue_message
        , msgid               =>    l_message_handle
      );
      commit;

      end;';

      dbms_scheduler.create_job(
        job_name            =>    self.promise_name || '_J'
        , job_type          =>    'PLSQL_BLOCK'
        , job_action        =>    l_anonymous_plsql_block
        , enabled           =>    true
      );

  end execute_promise;

  member procedure check_and_set_value(self in out promise)

  as

    l_promise_result      promise_result;
    l_dequeue_options     dbms_aq.dequeue_options_t;
    l_message_properties  dbms_aq.message_properties_t;
    l_first_dequeue       boolean := true;
    l_message_handle      raw(16);

    -- Exceptions
    l_exception_timeout   exception;
    pragma exception_init(l_exception_timeout, -25228);

  begin

      loop
        -- non-destructive dequeue
        l_dequeue_options.dequeue_mode := dbms_aq.browse;
        l_dequeue_options.wait := dbms_aq.no_wait;
        l_dequeue_options.visibility := dbms_aq.immediate;
        if l_first_dequeue then
          l_dequeue_options.navigation := dbms_aq.first_message;
        else
          l_dequeue_options.navigation := dbms_aq.next_message;
        end if;

        -- dequeue
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

        if l_promise_result.promise_name = self.promise_name then
          -- Set value or rejection. We have the result.
          if l_promise_result.promise_result = 'SUCCESS' then
            -- Set state to fulfilled and set the result value.
            -- self.set_state('fulfilled', l_promise_result.promise_value);
            self.state := 'fulfilled';
            self.val := l_promise_result.promise_value;
          elsif l_promise_result.promise_result = 'FAILURE' then
            -- Set state to rejected and set the rejection result.
            self.state := 'rejected';
            self.val := l_promise_result.promise_value;
          end if;
        end if;
      end loop;

      exception
        when l_exception_timeout then
          null;

  end check_and_set_value;

  member function getvalue(self in out promise)
  return sys.anydata

  as

    l_ret_val             sys.anydata := null;


  begin

    if self.state = 'pending' then
      -- We need to check if the result has been queued
      -- and if it has, set new state and value. If not return null.
      self.check_and_set_value;

      if self.state in ('rejected', 'fulfilled') then
        l_ret_val := self.val;
      else
        l_ret_val.setvarchar2(null);
      end if;
      return l_ret_val;
    elsif self.state in ('rejected', 'fulfilled') then
      -- We can return the value. We will never change once we are in this state.
      l_ret_val := self.val;
      return l_ret_val;
    else
      -- Dont know what happened here.
      raise_application_error(-20042, 'promise in invalid state: ' || self.state);
    end if;

  end getvalue;

  member function getvalue_number(self in out promise)
  return number

  as

    l_ret_val         number;

  begin

    if self.typeval = 1 then
      if self.state = 'pending' then
        self.check_and_set_value;
      end if;
      l_ret_val := sys.anydata.accessNumber(self.val);
      return l_ret_val;
    else
      raise_application_error(-20042, 'promise value not a number');
    end if;

  end getvalue_number;

  member function getvalue_varchar(self in out promise)
  return varchar2

  as

    l_ret_val       varchar2(32000);

  begin

    if self.typeval = 2 then
      if self.state = 'pending' then
        self.check_and_set_value;
      end if;
      l_ret_val := sys.anydata.accessVarchar2(self.val);
      return l_ret_val;
    else
      raise_application_error(-20042, 'promise value not a varchar2');
    end if;

  end getvalue_varchar;

end;
/
