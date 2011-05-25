------------------------------------------------------------------------------
--                                                                          --
--                         GNAT BACK-END COMPONENTS                         --
--                                                                          --
--                           A L F A . F I L T E R                          --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--             Copyright (C) 2011, Free Software Foundation, Inc.           --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT; see file COPYING3.  If not, go to --
-- http://www.gnu.org/licenses for a complete copy of the license.          --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Atree;        use Atree;
with Lib;
with Lib.Xref;
with Namet;        use Namet;
with Nlists;       use Nlists;
with Nmake;        use Nmake;
with Sem_Util;     use Sem_Util;
with Sinfo;        use Sinfo;
with Stand;        use Stand;

with ALFA.Common;     use ALFA.Common;
with ALFA.Definition; use ALFA.Definition;

package body ALFA.Filter is

   Standard_Why_Package      : List_Of_Nodes.List :=
      List_Of_Nodes.Empty_List;
   Standard_Why_Package_Name : constant String := "_standard";

   -----------------------
   -- Local Subprograms --
   -----------------------

   procedure Traverse_Subtree
     (N       : Node_Id;
      Process : access procedure (N : Node_Id));
   --  Traverse the subtree of N and call Process on selected nodes

   -----------------------------
   -- Filter_Compilation_Unit --
   -----------------------------

   procedure Filter_Compilation_Unit (N : Node_Id) is
      Prefix                 : constant String :=
         File_Name_Without_Suffix (Sloc (N));
      Types_Vars_Spec_Suffix : constant String := "__types_vars_spec";
      Types_Vars_Body_Suffix : constant String := "__types_vars_body";
      Subp_Spec_Suffix       : constant String := "__subp_spec";
      Main_Suffix            : constant String := "__package";

      Types_Vars_Spec : Why_Package :=
         Make_Empty_Why_Pack (Prefix & Types_Vars_Spec_Suffix);
      Types_Vars_Body : Why_Package :=
         Make_Empty_Why_Pack (Prefix & Types_Vars_Body_Suffix);
      Subp_Spec       : Why_Package :=
         Make_Empty_Why_Pack (Prefix & Subp_Spec_Suffix);

      Subp_Body       : Why_Package :=
         Make_Empty_Why_Pack (Prefix & Main_Suffix);

      --  All subprogram definitions should end up in this package, as it
      --  corresponds to the only Why file which is not included by other Why
      --  files, so that we will not redo the same proof more than once. In
      --  particular, subprogram bodies for expression functions, which may be
      --  originally declared in the package spec, should end up here.

      procedure Bucket_Dispatch
        (N          : Node_Id;
         Types_Vars : in out List_Of_Nodes.List;
         Subp_Spec  : in out List_Of_Nodes.List;
         Subp_Body  : in out List_Of_Nodes.List);
      --  If the Node belongs to the ALFA language, put it in one of the
      --  corresponding buckets (types or variables, subprograms) in argument.
      --  Also, introduce explicit type declarations for anonymous types.

      procedure Dispatch_Spec (N : Node_Id);
      --  Dispatch types, vars, subprogram decls to the corresponding buckets
      --  for specifications.

      procedure Dispatch_Body (N : Node_Id);
      --  Dispatch types, vars, subprograms to the corresponding buckets
      --  for bodies.

      ---------------------
      -- Bucket_Dispatch --
      ---------------------

      procedure Bucket_Dispatch
        (N          : Node_Id;
         Types_Vars : in out List_Of_Nodes.List;
         Subp_Spec  : in out List_Of_Nodes.List;
         Subp_Body  : in out List_Of_Nodes.List)
      is
      begin
         case Nkind (N) is
            when N_Subprogram_Declaration =>
               if Spec_Is_In_ALFA (Unique (Defining_Entity (N))) then
                  Subp_Spec.Append (N);
               end if;

            --  When seeing a stub, forward to the actual body

            when N_Subprogram_Body =>
               declare
                  Id : constant Unique_Entity_Id :=
                         Unique (Defining_Entity (N));

               begin
                  --  Create a subprogram declaration if not already present,
                  --  in order to generate a corresponding forward declaration.
                  --  Share specification between declaration and body, as
                  --  creating a specification after frontend analysis is bound
                  --  to be incomplete. Thus, the "Parent" field of the
                  --  specification now points only to the spec, not the body.

                  if Acts_As_Spec (N) then
                     Subp_Spec.Append
                       (Make_Subprogram_Declaration
                          (Sloc (N), Specification (N)));
                  end if;

                  if Body_Is_In_ALFA (Id) then
                     Subp_Body.Append (N);
                  end if;
               end;

            when N_Subprogram_Body_Stub =>
               declare
                  Body_N : constant Node_Id := Get_Body_From_Stub (N);
                  Id     : constant Unique_Entity_Id :=
                             Unique (Defining_Entity (Body_N));

               begin
                  if Is_Subprogram_Stub_Without_Prior_Declaration (N) then
                     Subp_Spec.Append
                       (Make_Subprogram_Declaration
                          (Sloc (Body_N), Specification (N)));
                  end if;

                  if Body_Is_In_ALFA (Id) then
                     Subp_Body.Append (Body_N);
                  end if;
               end;

            when N_Full_Type_Declaration | N_Subtype_Declaration =>
               Types_Vars.Append (N);

            when N_Object_Declaration =>
               --  Local variables introduced by the compiler should remain
               --  local.

               if (Comes_From_Source (Original_Node (N))
                    or else Is_Package_Level_Entity (Defining_Entity (N)))
                 and then Object_Is_In_ALFA (Unique (Defining_Entity (N)))
               then
                  case Nkind (Object_Definition (N)) is
                     when N_Identifier | N_Expanded_Name =>
                        null;

                     when N_Constrained_Array_Definition =>
                        declare
                           TyDef : constant Node_Id := Object_Definition (N);
                        begin
                           Types_Vars.Append
                             (Make_Full_Type_Declaration
                                (Sloc (N),
                                 New_Copy (Etype (Defining_Identifier (N))),
                                 Type_Definition => New_Copy (TyDef)));
                        end;

                     when others =>
                        null;

                  end case;
                  Types_Vars.Append (N);
               end if;

            when others =>
               null;

         end case;

      end Bucket_Dispatch;

      -------------------
      -- Dispatch_Spec --
      -------------------

      procedure Dispatch_Spec (N : Node_Id) is
      begin
         Bucket_Dispatch (N          => N,
                          Types_Vars => Types_Vars_Spec.WP_Decls,
                          Subp_Spec  => Subp_Spec.WP_Decls,
                          Subp_Body  => Subp_Body.WP_Decls);
      end Dispatch_Spec;

      -------------------
      -- Dispatch_Body --
      -------------------

      procedure Dispatch_Body (N : Node_Id) is
      begin
         Bucket_Dispatch (N          => N,
                          Types_Vars => Types_Vars_Body.WP_Decls,
                          Subp_Spec  => Subp_Body.WP_Decls,
                          Subp_Body  => Subp_Body.WP_Decls);
      end Dispatch_Body;

      Spec_Unit : Node_Id := Empty;
      Body_Unit : Node_Id := Empty;

   --  Start of processing for Filter_Compilation_Unit

   begin
      case Nkind (Unit (N)) is
         when N_Package_Body =>
            Spec_Unit :=
              Enclosing_Lib_Unit_Node (Corresponding_Spec (Unit (N)));
            Body_Unit := N;

         when N_Package_Declaration | N_Generic_Package_Declaration =>
            Spec_Unit := N;

         when N_Subprogram_Body =>
            if not Acts_As_Spec (Unit (N)) then
               Spec_Unit :=
                 Enclosing_Lib_Unit_Node (Corresponding_Spec (Unit (N)));
            end if;
            Body_Unit := N;

         when others =>
            raise Program_Error;
      end case;

      if Present (Spec_Unit) then
         Lib.Xref.ALFA.Traverse_Compilation_Unit
           (Spec_Unit, Dispatch_Spec'Unrestricted_Access,
            Inside_Stubs => True);
      end if;

      if Present (Body_Unit) then
         Lib.Xref.ALFA.Traverse_Compilation_Unit
           (Body_Unit, Dispatch_Body'Unrestricted_Access,
            Inside_Stubs => True);

         --  Sort the declarations just listed so that subprogram declarations
         --  precede subprogram bodies.

         declare
            function "<" (Left, Right : Node_Id) return Boolean;
            --  Ordering in which subprogram specs are first

            function "<" (Left, Right : Node_Id) return Boolean is
            begin
               return (Nkind (Left) = N_Subprogram_Declaration
                        and then Nkind (Right) /= N_Subprogram_Declaration);
            end "<";

            package Put_Spec_First is new List_Of_Nodes.Generic_Sorting ("<");

         begin
            Put_Spec_First.Sort (Subp_Body.WP_Decls);
         end;
      end if;

      --  Take into account dependencies
      --  Add standard package only to types_vars for spec
      Add_With_Clause (Types_Vars_Spec, Standard_Why_Package_Name);
      --  Add "vertical" dependencies for a single package
      Add_With_Clause (Types_Vars_Body, Types_Vars_Spec);
      Add_With_Clause (Subp_Spec, Types_Vars_Body);
      Add_With_Clause (Subp_Body, Subp_Spec);

      --  for each with clause in the package spec, add horizontal
      --  dependencies between spec packages
      if Present (Spec_Unit) then
         declare
            Cursor : Node_Id := First (Context_Items (Spec_Unit));
         begin
            while Present (Cursor) loop
               case Nkind (Cursor) is
                  when N_With_Clause =>
                     if not Implicit_With (Cursor)
                       and then
                         not Is_From_Standard_Library
                           (Sloc (Library_Unit (Cursor)))
                     then
                        declare
                           Pkg_Name : constant String :=
                               File_Name_Without_Suffix
                                 (Sloc (Library_Unit (Cursor)));
                        begin
                           Add_With_Clause
                              (Types_Vars_Spec,
                               Pkg_Name & Types_Vars_Spec_Suffix);
                           Add_With_Clause
                              (Subp_Spec,
                               Pkg_Name & Subp_Spec_Suffix);
                        end;
                     end if;

                  when others =>
                     null;
               end case;
               Next (Cursor);
            end loop;
         end;
      end if;

      --  Add diagonal dependencies for spec -> body dependencies
      if Present (Body_Unit) then
         declare
            Cursor : Node_Id := First (Context_Items (Body_Unit));
         begin
            while Present (Cursor) loop
               case Nkind (Cursor) is
                  when N_With_Clause =>
                     declare
                        Pkg_Name : constant String :=
                                     File_Name_Without_Suffix
                                       (Sloc (Library_Unit (Cursor)));
                     begin
                        if not Implicit_With (Cursor)
                          and then
                            not Is_From_Standard_Library
                              (Sloc (Library_Unit (Cursor)))
                        then
                           Add_With_Clause
                             (Types_Vars_Body,
                              Pkg_Name & Types_Vars_Spec_Suffix);
                           Add_With_Clause
                             (Subp_Spec,
                              Pkg_Name & Types_Vars_Body_Suffix);
                           Add_With_Clause
                             (Subp_Body,
                              Pkg_Name & Subp_Spec_Suffix);
                        end if;
                     end;

                  when others =>
                     null;

               end case;
               Next (Cursor);
            end loop;
         end;
      end if;

      --  If the current package is a child package, add the implicit with
      --  clause from the child spec to the parent spec
      declare
         Def_Unit_Name : Node_Id := Empty;
      begin
         case Nkind (Unit (N)) is
            when N_Package_Declaration =>
               Def_Unit_Name :=
                  Defining_Unit_Name (Specification (Unit (N)));

            when N_Package_Body =>
               Def_Unit_Name := Defining_Unit_Name ((Unit (N)));

            when others =>
               null;
         end case;

         if Present (Def_Unit_Name) and then
            Nkind (Def_Unit_Name) = N_Defining_Program_Unit_Name then
               Add_With_Clause
                  (Types_Vars_Spec,
                   Get_Name_String (Chars (Name (Def_Unit_Name))) &
                     Types_Vars_Spec_Suffix);
         end if;
      end;

      ALFA_Compilation_Units.Append (Types_Vars_Spec);
      ALFA_Compilation_Units.Append (Types_Vars_Body);
      ALFA_Compilation_Units.Append (Subp_Spec);
      ALFA_Compilation_Units.Append (Subp_Body);
   end Filter_Compilation_Unit;

   -----------------------------
   -- Filter_Standard_Package --
   -----------------------------

   function Filter_Standard_Package return List_Of_Nodes.List is
      use List_Of_Nodes;
   begin
      if Is_Empty (Standard_Why_Package) then
         declare
            Decl          : Node_Id :=
               First (Visible_Declarations (
                 Specification (Standard_Package_Node)));
         begin
            while Present (Decl) loop
               case Nkind (Decl) is
                  when N_Full_Type_Declaration
                    | N_Subtype_Declaration =>
                     if Type_Is_In_ALFA (Unique (Defining_Entity (Decl))) then
                        Standard_Why_Package.Append (Decl);
                     end if;

                  when N_Object_Declaration =>
                     if Object_Is_In_ALFA
                       (Unique (Defining_Entity (Decl)))
                     then
                        Standard_Why_Package.Append (Decl);
                     end if;

                  when others =>
                     null;
               end case;

               Next (Decl);
            end loop;

         end;
      end if;

      return Standard_Why_Package;
   end Filter_Standard_Package;

   ----------------------
   -- Traverse_Subtree --
   ----------------------

   procedure Traverse_Subtree
     (N       : Node_Id;
      Process : access procedure (N : Node_Id))
   is
      procedure Traverse_List (L : List_Id);
      --  Traverse through the list of nodes L

      procedure Traverse_List (L : List_Id) is
         Cur : Node_Id;
      begin
         Cur := First (L);
         while Present (Cur) loop
            Traverse_Subtree (Cur, Process);
            Next (Cur);
         end loop;
      end Traverse_List;

   begin
      Process (N);

      case Nkind (N) is
         when N_Package_Declaration =>
            Traverse_List (Visible_Declarations (Specification (N)));
            Traverse_List (Private_Declarations (Specification (N)));

         when N_Package_Body =>
            Traverse_Subtree
              (Parent (Parent (Corresponding_Spec (N))), Process);
            Traverse_List (Declarations (N));

         when others =>
            null;
            --  ??? Later on complete this by raising Program_Error
            --  for unexpected cases.
      end case;
   end Traverse_Subtree;

end ALFA.Filter;
