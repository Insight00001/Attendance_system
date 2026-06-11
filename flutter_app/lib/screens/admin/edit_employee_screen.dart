import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../bloc/employee/employee_bloc.dart';
import '../../models/models.dart';
import '../../themes/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/loading_overlay.dart';

class EditEmployeeScreen extends StatefulWidget {
  final EmployeeModel employee;
  const EditEmployeeScreen({super.key, required this.employee});
  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName     = TextEditingController(text: widget.employee.firstName);
  late final _lastName      = TextEditingController(text: widget.employee.lastName);
  late final _phone         = TextEditingController(text: widget.employee.phone ?? '');
  late final _jobTitle      = TextEditingController(text: widget.employee.jobTitle ?? '');
  late final _shiftStart    = TextEditingController(text: widget.employee.shiftStart ?? '08:00');
  late final _shiftEnd      = TextEditingController(text: widget.employee.shiftEnd ?? '17:00');
  late final _lateThreshold = TextEditingController(text: widget.employee.lateThreshold.toString());

  late String _gender = widget.employee.gender ?? 'prefer_not_to_say';
  late String _status = widget.employee.employmentStatus;
  String? _deptId;
  String? _roleId;
  Uint8List? _newPhotoBytes;
  String?    _newPhotoName;
  List<DepartmentModel> _departments = [];
  List<RoleModel>       _roles       = [];

  @override
  void initState() {
    super.initState();
    _deptId = widget.employee.department?.id;
    _roleId = widget.employee.role?.id;
    context.read<EmployeeBloc>().add(EmployeeLoadDepartments());
  }

  @override
  void dispose() {
    _firstName.dispose(); _lastName.dispose(); _phone.dispose();
    _jobTitle.dispose(); _shiftStart.dispose(); _shiftEnd.dispose();
    _lateThreshold.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _newPhotoBytes = bytes;
        _newPhotoName  = picked.name;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<EmployeeBloc>().add(EmployeeUpdate(
      widget.employee.id,
      {
        'first_name':        _firstName.text.trim(),
        'last_name':         _lastName.text.trim(),
        'phone':             _phone.text.trim(),
        'job_title':         _jobTitle.text.trim(),
        'gender':            _gender,
        'employment_status': _status,
        'shift_start':       _shiftStart.text.trim(),
        'shift_end':         _shiftEnd.text.trim(),
        'late_threshold':    int.tryParse(_lateThreshold.text.trim()) ?? 15,
        if (_deptId != null) 'department_id': _deptId,
        if (_roleId != null) 'role_id':       _roleId,
      },
      photoBytes: _newPhotoBytes,
      photoName:  _newPhotoName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EmployeeBloc, EmployeeState>(
      listener: (context, state) {
        if (state is EmployeeDepartmentsLoaded) {
          setState(() {
            _departments = state.departments;
            _roles       = state.roles;
          });
        } else if (state is EmployeeOperationSuccess) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context, true);
          messenger.showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.accentGreen));
        } else if (state is EmployeeError) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.accentRed));
        }
      },
      child: BlocBuilder<EmployeeBloc, EmployeeState>(
        builder: (context, state) => LoadingOverlay(
          isLoading: state is EmployeeLoading,
          child: Scaffold(
            appBar: AppBar(title: Text('Edit ${widget.employee.firstName}')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo
                      Center(
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: Stack(children: [
                            CircleAvatar(
                              radius: 52,
                              backgroundColor: const Color(0xFFEFF6FF),
                              backgroundImage: _newPhotoBytes != null
                                  ? MemoryImage(_newPhotoBytes!) : null,
                              child: _newPhotoBytes == null
                                  ? Text(widget.employee.avatarInitials,
                                      style: const TextStyle(fontSize: 32,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primaryBlue))
                                  : null,
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                    color: AppTheme.primaryBlue,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(children: [
                        Expanded(child: AppTextField(controller: _firstName,
                            label: 'First Name',
                            validator: (v) => v!.isEmpty ? 'Required' : null)),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(controller: _lastName,
                            label: 'Last Name',
                            validator: (v) => v!.isEmpty ? 'Required' : null)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: AppTextField(controller: _phone,
                            label: 'Phone', keyboardType: TextInputType.phone,
                            prefixIcon: Icons.phone_outlined)),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(controller: _jobTitle,
                            label: 'Job Title')),
                      ]),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _deptId,
                        hint: const Text('Select Department'),
                        decoration: const InputDecoration(labelText: 'Department'),
                        items: _departments.map((d) => DropdownMenuItem(
                            value: d.id, child: Text(d.name))).toList(),
                        onChanged: (v) => setState(() => _deptId = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _roleId,
                        hint: const Text('Select Role'),
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: _roles.map((r) => DropdownMenuItem(
                            value: r.id, child: Text(r.name))).toList(),
                        onChanged: (v) => setState(() => _roleId = v),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: AppTextField(controller: _shiftStart,
                            label: 'Shift Start',
                            prefixIcon: Icons.login_outlined)),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(controller: _shiftEnd,
                            label: 'Shift End',
                            prefixIcon: Icons.logout_outlined)),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(controller: _lateThreshold,
                            label: 'Late (mins)',
                            keyboardType: TextInputType.number)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: DropdownButtonFormField<String>(
                          value: _status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'active',    child: Text('Active')),
                            DropdownMenuItem(value: 'inactive',  child: Text('Inactive')),
                            DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                          ],
                          onChanged: (v) => setState(() => _status = v ?? _status),
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: const InputDecoration(labelText: 'Gender'),
                          items: const [
                            DropdownMenuItem(value: 'male',             child: Text('Male')),
                            DropdownMenuItem(value: 'female',           child: Text('Female')),
                            DropdownMenuItem(value: 'other',            child: Text('Other')),
                            DropdownMenuItem(value: 'prefer_not_to_say', child: Text('Prefer not to say')),
                          ],
                          onChanged: (v) => setState(() => _gender = v ?? _gender),
                        )),
                      ]),
                      const SizedBox(height: 32),
                      AppButton(label: 'Save Changes', onPressed: _submit),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}