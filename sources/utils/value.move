module openmove::value {
  use std::error;

  struct Value<phantom Tag> has store {
    value: u64,
  }

  const EDESTRUCTION_OF_NONZERO_VALUE: u64 = 1;
  const EVALUE_INSUFFICIENT: u64 = 2;

  public fun make_value<T>(v: u64): Value<T> {
    Value { value: v, }
  }

  public fun merge_value<T>(c: &mut Value<T>, o: Value<T>) {
    let Value { value } = o;
    c.value = c.value + value ;
  }

  public fun split_value<T>(c: &mut Value<T>, value: u64): Value<T> {
    assert!(c.value >= value , error::invalid_argument(EVALUE_INSUFFICIENT));
    c.value = c.value - value;
    Value<T> { value, }
  }

  public fun split_value_all<T>(c: &mut Value<T>): Value<T> {
    let v = c.value;
    split_value(c, v)
  }

  public fun destory_zero<T>(zero_Value: Value<T>) {
    let Value { value } = zero_Value;
    assert!(value == 0, error::invalid_argument(EDESTRUCTION_OF_NONZERO_VALUE))
  }

  // force destroy a Value
  public fun destory<T>(value: Value<T>) {
    let Value { value: _ } = value;
  }

  public fun value<T>(c: &Value<T>): u64 {
    c.value
  }
}