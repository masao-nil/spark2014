package Const is 

  type D is new Integer range 1 .. 10;

  type A is array (D range <>) of Integer;

  type T (K : D) is record
      Som : Integer;
      Arr : A (1 .. K);
    end record;

  procedure Simple (X : T);

  procedure Modify (X : in out T);
end Const;
