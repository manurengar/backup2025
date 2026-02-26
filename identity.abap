*&---------------------------------------------------------------------*
*& Report  ZGLXX_PRO_RE_ROLES
*&
*&---------------------------------------------------------------------*
*&
*&
*&---------------------------------------------------------------------*

REPORT zglxx_pro_re_etl_mrg.


DATA: lv_uname TYPE syuname,
      lt_roles TYPE TABLE OF bapiagr,
      wa_roles TYPE bapiagr,
      lt_ret   TYPE TABLE OF bapiret2.
DATA rol TYPE agr_name.
DATA vrol TYPE RANGE OF agr_name.
DATA v_rol LIKE LINE OF vrol.
DATA lv_message TYPE string.
DATA lv_ret LIKE LINE OF lt_ret.

DATA profiles TYPE TABLE OF bapiprof.
DATA ls_profiles LIKE LINE OF profiles.
DATA user_profiles LIKE LINE OF profiles OCCURS 0 WITH HEADER LINE.
DATA i_usr10 LIKE usr10 OCCURS 0 WITH HEADER LINE.
DATA lt_profiles TYPE TABLE OF bapiprof.
FIELD-SYMBOLS <prof> LIKE LINE OF lt_profiles.

******************  ******************************
INCLUDE zglxx_pro_in_etl_data.

SELECT-OPTIONS: s_user FOR bname NO INTERVALS.


START-OF-SELECTION.

  LOOP AT s_user ASSIGNING FIELD-SYMBOL(<user>).
    INSERT INITIAL LINE INTO TABLE lt_bname REFERENCE INTO lr_bname.
    APPEND INITIAL LINE TO users_complete ASSIGNING FIELD-SYMBOL(<user_comp>).
    <user_comp>-bname = <user>-low.
    lr_bname->bname = <user>-low .
  ENDLOOP.


  TRY.
      " get instances for users
      "------------------------------------------------------------------------------------------
      APPEND INITIAL LINE TO lt_nodes_prefetch REFERENCE INTO lr_nodes_prefetch.
      lr_nodes_prefetch->nodename = if_identity_definition=>gc_node_profile.
      APPEND INITIAL LINE TO lt_nodes_prefetch REFERENCE INTO lr_nodes_prefetch.
      lr_nodes_prefetch->nodename = if_identity_definition=>gc_node_reference_user.

      cl_identity_factory=>retrieve( EXPORTING it_bname                = lt_bname
                                               it_nodes_prefetch       = lt_nodes_prefetch
                                     IMPORTING et_node_root            = lt_node_root
                                               et_bname_not_exist      = lt_bname_not_exist
                                               et_bname_not_authorized = lt_bname_not_authorized
                                               eo_msg_buffer           = lr_msg_buffer
                                              ).
      LOOP AT lt_bname_not_exist REFERENCE INTO lr_bname.

        IF ( 1 = 0 ). MESSAGE e003(suid01) WITH lr_bname->bname. ENDIF. "User &1 does not exist; enter a valid user name

        APPEND INITIAL LINE TO lt_root_nodes REFERENCE INTO lr_root_nodes.
        lr_root_nodes->bname = lr_bname->bname.
        cl_susr_basic_tools=>add_message_to_return( EXPORTING iv_type   = 'E'
                                                              iv_cl     = 'SUID01'
                                                              iv_number = '003'
                                                              iv_par1   = lr_bname->bname
                                                    CHANGING  cv_return = lr_root_nodes->return
                                                            ).
      ENDLOOP.

      LOOP AT lt_bname_not_authorized REFERENCE INTO lr_bname.
        CLEAR: lt_messages[]
        .
        lv_miss_user = lv_miss_user + 1.

        APPEND INITIAL LINE TO lt_root_nodes REFERENCE INTO lr_root_nodes.
        lr_root_nodes->bname = lr_bname->bname.

        cl_identity_tools=>msg_buffer_retrieve( EXPORTING iv_bname      = lr_bname->bname
                                                          io_msg_buffer = lr_msg_buffer
                                                CHANGING  ct_messages   = lt_messages
                                                        ).
        LOOP AT lt_messages REFERENCE INTO lr_messages.
          cl_susr_basic_tools=>add_message_to_return( EXPORTING iv_type   = lr_messages->msgty
                                                                iv_cl     = lr_messages->msgid
                                                                iv_number = lr_messages->msgno
                                                                iv_par1   = lr_messages->msgv1
                                                                iv_par2   = lr_messages->msgv2
                                                                iv_par3   = lr_messages->msgv3
                                                                iv_par4   = lr_messages->msgv4
                                                      CHANGING  cv_return = lr_root_nodes->return
                                                              ).
        ENDLOOP.
      ENDLOOP.

      SORT lt_node_root BY bname.
      " get instances for related reference users
      "------------------------------------------------------------------------------------------
      APPEND INITIAL LINE TO lt_nodes_prefetch REFERENCE INTO lr_nodes_prefetch.
      lr_nodes_prefetch->nodename = if_identity_definition=>gc_node_profile.

      LOOP AT lt_node_root REFERENCE INTO lr_node_root.

        CLEAR: lt_messages
        .
        APPEND INITIAL LINE TO lt_root_nodes REFERENCE INTO lr_root_nodes.
        lr_root_nodes->bname = lr_node_root->bname.
        lr_root_nodes->idref = lr_node_root->idref.

        READ TABLE users_complete WITH  KEY bname = lr_node_root->bname REFERENCE INTO lr_users_complete.
        IF ( lr_users_complete          IS NOT BOUND   ) OR
        ( lr_users_complete->refuser IS     INITIAL ). "omit reading refuser if it isn't requested
          CONTINUE.
        ENDIF.

        lr_node_root->idref->get_reference_user( IMPORTING es_reference_user = ls_node_ref_user
                                                           eo_msg_buffer     = lr_msg_buffer
                                                          ).
        cl_identity_tools=>msg_buffer_retrieve( EXPORTING iv_bname      = lr_node_root->bname
                                                          io_msg_buffer = lr_msg_buffer
                                                CHANGING  ct_messages   = lt_messages
                                                        ).
        LOOP AT lt_messages REFERENCE INTO lr_messages.
          cl_susr_basic_tools=>add_message_to_return( EXPORTING iv_type   = lr_messages->msgty
                                                                iv_cl     = lr_messages->msgid
                                                                iv_number = lr_messages->msgno
                                                                iv_par1   = lr_messages->msgv1
                                                                iv_par2   = lr_messages->msgv2
                                                                iv_par3   = lr_messages->msgv3
                                                                iv_par4   = lr_messages->msgv4
                                                      CHANGING  cv_return = lr_root_nodes->return
                                                              ).
        ENDLOOP.
        IF ( ls_node_ref_user-refuser IS INITIAL                    ) OR
        ( ls_node_ref_user-refuser <> lr_users_complete->refuser ).  "The really assigend refuser differs from handed over!!!
          CONTINUE.
        ENDIF.

        READ TABLE lt_refuser_rel WITH KEY bname   = lr_node_root->bname
        refuser = ls_node_ref_user-refuser
        BINARY SEARCH TRANSPORTING NO FIELDS.
        IF ( sy-subrc <> 0 ).
          "... usual case
          INSERT INITIAL LINE INTO lt_refuser_rel INDEX sy-tabix REFERENCE INTO lr_refuser_rel.
          lr_refuser_rel->bname   = lr_node_root->bname.
          lr_refuser_rel->refuser = ls_node_ref_user-refuser.

          "... check if this reference user is already instantiated
          READ TABLE lt_refuser_nodes WITH KEY refuser = ls_node_ref_user-refuser BINARY SEARCH REFERENCE INTO lr_refuser_nodes.

          IF ( sy-subrc = 0 ).
            "store known reference to the refusers node to this user, too
            lr_refuser_rel->refuser_node = lr_refuser_nodes.

          ELSE.
            INSERT INITIAL LINE INTO lt_refuser_nodes INDEX sy-tabix REFERENCE INTO lr_refuser_nodes.
            lr_refuser_rel->refuser_node = lr_refuser_nodes.      "store reference pointing to the new refusers node
            lr_refuser_nodes->refuser    = ls_node_ref_user-refuser.

            "get the instance of the new refuser
            CLEAR: lt_bname_ref[]
            , lt_messages[]
            , lt_bname_not_exist[]
            , lt_bname_not_authorized[]
            .

            lt_bname_ref = VALUE #( ( bname = ls_node_ref_user-refuser ) ).

            cl_identity_factory=>retrieve( EXPORTING it_bname                = lt_bname_ref
                                                     it_nodes_prefetch       = lt_nodes_prefetch
                                           IMPORTING et_node_root            = lt_node_root_ref
                                                     et_bname_not_exist      = lt_bname_not_exist
                                                     et_bname_not_authorized = lt_bname_not_authorized
                                                     eo_msg_buffer           = lr_msg_buffer
                                                    ).
            READ TABLE lt_bname_not_exist INDEX 1 REFERENCE INTO lr_bname.
            IF ( sy-subrc = 0 ).
              APPEND INITIAL LINE TO lt_refuser_nodes REFERENCE INTO lr_refuser_nodes.
              lr_refuser_nodes->refuser = lr_bname->bname.
              IF ( 1 = 0 ). MESSAGE e003(suid01) WITH lr_bname->bname. ENDIF. "User &1 does not exist; enter a valid user name

              cl_susr_basic_tools=>add_message_to_return( EXPORTING iv_type   = 'E'
                                                                    iv_cl     = 'SUID01'
                                                                    iv_number = '003'
                                                                    iv_par1   = lr_bname->bname
                                                          CHANGING  cv_return = lr_refuser_nodes->return
                                                                  ).
              CONTINUE.
            ENDIF.   "refuser do not exist

            READ TABLE lt_bname_not_authorized INDEX 1 REFERENCE INTO lr_bname.
            IF ( sy-subrc = 0 ).
              CLEAR: lt_messages[]
              .
              APPEND INITIAL LINE TO lt_refuser_nodes REFERENCE INTO lr_refuser_nodes.
              lr_refuser_nodes->refuser = lr_bname->bname.
              cl_identity_tools=>msg_buffer_retrieve( EXPORTING iv_bname      = lr_bname->bname
                                                                io_msg_buffer = lr_msg_buffer
                                                      CHANGING  ct_messages   = lt_messages
                                                              ).
              LOOP AT lt_messages REFERENCE INTO lr_messages.
                cl_susr_basic_tools=>add_message_to_return( EXPORTING iv_type   = lr_messages->msgty
                                                                      iv_cl     = lr_messages->msgid
                                                                      iv_number = lr_messages->msgno
                                                                      iv_par1   = lr_messages->msgv1
                                                                      iv_par2   = lr_messages->msgv2
                                                                      iv_par3   = lr_messages->msgv3
                                                                      iv_par4   = lr_messages->msgv4
                                                            CHANGING  cv_return = lr_refuser_nodes->return
                                                                    ).
              ENDLOOP.

              CONTINUE.

            ENDIF.   "not authorized to read the refuser

            "... get profile assignments of the reference user
            READ TABLE lt_node_root_ref INDEX 1 REFERENCE INTO lr_node_root_ref.
            IF ( sy-subrc = 0 ).
              lr_refuser_nodes->idref = lr_node_root_ref->idref.

              CLEAR: lt_messages
              .
              lr_refuser_nodes->idref->get_profiles( EXPORTING iv_get_prof_details = 'X'    "profile text and typ will be read, too
                                                     IMPORTING et_profiles         = lr_refuser_nodes->profiles[]
                                                               eo_msg_buffer       = lr_msg_buffer
                                                              ).
              cl_identity_tools=>msg_buffer_retrieve( EXPORTING iv_bname      = lr_refuser_nodes->refuser
                                                                io_msg_buffer = lr_msg_buffer
                                                      CHANGING  ct_messages   = lt_messages
                                                              ).
              LOOP AT lt_messages REFERENCE INTO lr_messages.
                cl_susr_basic_tools=>add_message_to_return( EXPORTING iv_type   = lr_messages->msgty
                                                                      iv_cl     = lr_messages->msgid
                                                                      iv_number = lr_messages->msgno
                                                                      iv_par1   = lr_messages->msgv1
                                                                      iv_par2   = lr_messages->msgv2
                                                                      iv_par3   = lr_messages->msgv3
                                                                      iv_par4   = lr_messages->msgv4
                                                            CHANGING  cv_return = lr_refuser_nodes->return
                                                                    ).
              ENDLOOP.

              lr_refuser_nodes->profiles_read = abap_true.

            ENDIF.   "refuser succesfully read

          ENDIF.   "refuser already known

        ENDIF.  "bname <-> refuser relation already stored

      ENDLOOP.   "at lt_node_root

      SORT lt_root_nodes BY bname.

      "------------------------------------------------------------------------------------------
      " get profiles for users
      LOOP AT lt_root_nodes REFERENCE INTO lr_root_nodes WHERE NOT idref IS INITIAL.

        CLEAR: lt_messages
        .
        lr_root_nodes->idref->get_profiles( EXPORTING iv_get_prof_details = 'X'    "profile text and typ will be read, too
                                            IMPORTING et_profiles         = lr_root_nodes->profiles
                                                      eo_msg_buffer       = lr_msg_buffer
                                                     ).

        READ TABLE lr_root_nodes->profiles ASSIGNING FIELD-SYMBOL(<sapall>) WITH KEY profile = 'SAP_ALL'.
        IF sy-subrc IS NOT INITIAL.
          APPEND INITIAL LINE TO lr_root_nodes->profiles ASSIGNING FIELD-SYMBOL(<profiles>).
          <profiles>-profile = 'SAP_ALL'.
          <profiles>-type = 'C'.
          <profiles>-aktps = 'A'.
          <profiles>-change_mode = 'I'.
        ELSE.
          DELETE lr_root_nodes->profiles FROM <sapall>.
        ENDIF.


*        " Adjust internal buffer
*        CALL METHOD lr_root_nodes->idref->profile_merge_to_result
*          EXPORTING
*            io_msg_buffer   = lr_msg_buffer
*            io_notify       = go_notify
*          IMPORTING
*            et_user_profile = lt_user_profile
*          CHANGING
*            ct_profiles     = ct_profiles.

        " Exporting: Import table + Key Handle
*        APPEND LINES OF ct_profiles TO et_node_profiles.

        " --- write new profiles into segments
*        CALL METHOD lr_root_nodes->idref->profile_write_to_segment
*          EXPORTING
*            it_user_profile = lr_root_nodes->profiles.

*
        lr_root_nodes->idref->set_profiles( EXPORTING it_profiles      = lr_root_nodes->profiles
                                            IMPORTING eo_msg_buffer    = lr_msg_buffer
                                                      eo_notify        = DATA(o_notify)
                                                      et_node_profiles = DATA(o_node_profiles) ).

        cl_identity_tools=>msg_buffer_retrieve( EXPORTING iv_bname      = lr_root_nodes->bname
                                                          io_msg_buffer = lr_msg_buffer
                                                CHANGING  ct_messages   = lt_messages
                                                        ).
        LOOP AT lt_messages REFERENCE INTO lr_messages.
          cl_susr_basic_tools=>add_message_to_return( EXPORTING iv_type   = lr_messages->msgty
                                                                iv_cl     = lr_messages->msgid
                                                                iv_number = lr_messages->msgno
                                                                iv_par1   = lr_messages->msgv1
                                                                iv_par2   = lr_messages->msgv2
                                                                iv_par3   = lr_messages->msgv3
                                                                iv_par4   = lr_messages->msgv4
                                                      CHANGING  cv_return = lr_root_nodes->return
                                                              ).
        ENDLOOP.

        lr_root_nodes->profiles_read = abap_true.

      ENDLOOP.
    CATCH cx_suid_identity INTO lr_cx_suid_identity.
      cl_identity_tools=>message_suid_technical_error( EXPORTING ix_suid_identity = lr_cx_suid_identity
                                                       IMPORTING es_return        = ls_return
                                                                ).
      WRITE lr_cx_suid_identity->get_text( ).
  ENDTRY.

  WRITE 'a'.
