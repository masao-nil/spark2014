pragma Unevaluated_Use_Of_Old (Allow);
with Conts.Functional.Sequences;
pragma Elaborate_All (Conts.Functional.Sequences);
with Conts.Functional.Sets;
pragma Elaborate_All (Conts.Functional.Sets);
with Conts;
use type Conts.Count_Type;

package List_Mod_Allocator with
  SPARK_Mode,
  Abstract_State    => State,
  Initializes       => State,
  Initial_Condition => All_Available and Is_Valid
is
   pragma Elaborate_Body;

   Capacity : constant := 10_000;

   type Resource is new Integer range 0 .. Capacity;
   subtype Valid_Resource is Resource range 1 .. Capacity;

   No_Resource : constant Resource := 0;

   function Is_Available (Res : Resource) return Boolean;
   function Is_Allocated (Res : Resource) return Boolean;

   function All_Available return Boolean with Ghost;

   package M with Ghost is
      package S1 is new Conts.Functional.Sequences (Index_Type => Positive,
                                                    Element_Type => Resource);
      use S1;

      package S2 is new Conts.Functional.Sets (Element_Type => Resource);
      use S2;

      type T is record
         Available : Sequence;
         Allocated : S2.Set;
      end record;

      function Mem (S : Sequence; E : Resource) return Boolean is
        (for some I in 1 .. Integer (Length (S)) => Get (S, I) = E);

      function Is_Prepend
        (S : Sequence; E : Resource; Result : Sequence) return Boolean
      --  Returns True if Result is S prepended with E.

      is
        (Length (S) < Conts.Count_Type'Last
         and then Length (Result) = Length (S) + 1
         and then Get (Result, 1) = E
         and then (for all M in 1 .. Integer (Length (S)) =>
                        Get (Result, M + 1) = Get (S, M)));

      function "=" (X, Y : T) return Boolean is
        (X.Available = Y.Available
           and then
         X.Allocated = Y.Allocated);

      function Is_Well_Formed return Boolean;

      function Model_Is_Well_Formed (M : T) return Boolean;

      function Model return T with
        Pre  => Is_Well_Formed,
        Post => Model_Is_Well_Formed (Model'Result);

      function Is_Valid return Boolean;

   end M;

   use M; use M.S1; use M.S2;

   procedure Alloc (Res : out Resource) with
     Pre  => Is_Valid,
     Post => Is_Valid,
     Contract_Cases =>

       --  When no resource is available, return the special value No_Resource
       --  with the allocator unmodified.

       (Length (Model.Available) = 0 =>
          Res = No_Resource
            and then
          Model = Model'Old,

        --  Otherwise, return an available resource which becomes allocated

        others =>
          M.Is_Prepend (Model.Available, Res, Result => Model.Available'Old)
            and then
          Is_Add (Model.Allocated'Old, Res, Result => Model.Allocated));

   procedure Free (Res : Resource) with
     Pre  => Is_Valid,
     Post => Is_Valid,
     Contract_Cases =>

       --  When the resource is allocated, make it available

       (Mem (Model.Allocated, Res) =>
          M.Is_Prepend (Model.Available'Old, Res, Result => Model.Available)
            and then
          Is_Add (Model.Allocated, Res, Result => Model.Allocated'Old),

        --  Otherwise, do nothing

        others =>
          Model = Model'Old);

end List_Mod_Allocator;
