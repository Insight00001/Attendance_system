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

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});
  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _jobTitle = TextEditingController();
  String _gender = 'prefer_not_to_say';
  String? _deptId;
  String? _roleId;
  Uint8List? _photoBytes;
  String? _photoName;
  List<DepartmentModel> _departments = [];
  List<RoleModel> _roles = [];

  @override
  void initState() {
    super.initState();
    context.read<EmployeeBloc>().add(EmployeeLoadDepartments());
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _jobTitle.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _photoBytes = bytes;
        _photoName = picked.name;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<EmployeeBloc>().add(EmployeeCreate(
      {
        'email': _email.text.trim(),
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'phone': _phone.text.trim(),
        'job_title': _jobTitle.text.trim(),
        'gender': _gender,
        if (_deptId != null) 'department_id': _deptId,
        if (_roleId != null) 'role_id': _roleId,
      },
      photoBytes: _photoBytes,
      photoName: _photoName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EmployeeBloc, EmployeeState>(
      listener: (context, state) {
        if (state is EmployeeDepartmentsLoaded) {
          setState(() {
            _departments = state.departments;
            _roles = state.roles;
          });
        } else if (state is EmployeeOperationSuccess) {
          final messenger=ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(const SnackBar(
              content: Text('Employee created successfully'),
              backgroundColor: AppTheme.accentGreen));
         
        } else if (state is EmployeeError) {
          if(!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.accentRed));
        }
      },
      child: BlocBuilder<EmployeeBloc, EmployeeState>(
        builder: (context, state) => LoadingOverlay(
          isLoading: state is EmployeeLoading,
          child: Scaffold(
            appBar: AppBar(title: const Text('Add Employee')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: CircleAvatar(
                            radius: 52,
                            backgroundColor:
                                const Color(0xFFEFF6FF),
                            backgroundImage: _photoBytes != null
                                ? MemoryImage(_photoBytes!)
                                : null,
                            child: _photoBytes == null
                                ? const Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.camera_alt_outlined,
                                          color: AppTheme.primaryBlue,
                                          size: 28),
                                      SizedBox(height: 4),
                                      Text('Add Photo',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  AppTheme.primaryBlue)),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'Photo is used for face recognition',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(children: [
                        Expanded(
                          child: AppTextField(
                            controller: _firstName,
                            label: 'First Name',
                            validator: (v) =>
                                (v?.isEmpty ?? true) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            controller: _lastName,
                            label: 'Last Name',
                            validator: (v) =>
                                (v?.isEmpty ?? true) ? 'Required' : null,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _email,
                        label: 'Email Address',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.email_outlined,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: AppTextField(
                            controller: _phone,
                            label: 'Phone',
                            keyboardType: TextInputType.phone,
                            prefixIcon: Icons.phone_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            controller: _jobTitle,
                            label: 'Job Title',
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _deptId,
                        hint: const Text('Select Department'),
                        decoration: const InputDecoration(
                            labelText: 'Department'),
                        items: _departments
                            .map((d) => DropdownMenuItem(
                                value: d.id, child: Text(d.name)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _deptId = v),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _roleId,
                        hint: const Text('Select Role'),
                        decoration:
                            const InputDecoration(labelText: 'Role'),
                        items: _roles
                            .map((r) => DropdownMenuItem(
                                value: r.id, child: Text(r.name)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _roleId = v),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _gender,
                        decoration:
                            const InputDecoration(labelText: 'Gender'),
                        items: const [
                          DropdownMenuItem(
                              value: 'male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'female', child: Text('Female')),
                          DropdownMenuItem(
                              value: 'other', child: Text('Other')),
                          DropdownMenuItem(
                              value: 'prefer_not_to_say',
                              child: Text('Prefer not to say')),
                        ],
                        onChanged: (v) => setState(
                            () => _gender = v ?? _gender),
                      ),
                      const SizedBox(height: 32),
                      AppButton(
                          label: 'Create Employee', onPressed: _submit),
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
