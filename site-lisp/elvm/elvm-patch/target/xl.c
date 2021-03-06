#include <ir/ir.h>
#include <target/util.h>

static void init_state_xl(Data* data) {
  emit_line("(defpackage :elvm-compiled (:use :lisp))");
  emit_line("(in-package :elvm-compiled)");
  emit_line("(export '(main))");
  for (int i = 0; i < 7; i++) {
    emit_line("(defvar %s 0)", reg_names[i]);
  }
  emit_line("(defvar mem nil)");
  emit_line("(defparameter mem-init '(");
  for (int mp = 0; data; data = data->next, mp++) {
    if (data->v) {
      emit_line("  (%d . %d)", mp, data->v);
    }
  }
  emit_line("))");
  emit_line("(defvar elvm-running nil)");
  emit_line("(defvar elvm-input nil)");
  emit_line("(defvar elvm-output nil)");
}

static void xl_emit_func_prologue(int func_id) {
  emit_line("");
  emit_line("(defun elvm-func%d ()", func_id);
  inc_indent();
  emit_line("(while (and (<= %d pc) (< pc %d) elvm-running)",
            func_id * CHUNKED_FUNC_SIZE, (func_id + 1) * CHUNKED_FUNC_SIZE);
  inc_indent();
  emit_line("(case pc");
  emit_line("(-1 nil");
  inc_indent();
}

static void xl_emit_func_epilogue(void) {
  dec_indent();
  emit_line("))");
  emit_line("(setq pc (+ pc 1))");
  dec_indent();
  emit_line(")");
  dec_indent();
  emit_line(")");
}

static void xl_emit_pc_change(int pc) {
  emit_line(")");
  emit_line("");
  dec_indent();
  emit_line("(%d", pc);
  inc_indent();
}

static const char* xl_cmp_str(Inst* inst) {
  int op = normalize_cond(inst->op, false);
  const char* fmt;
  switch (op) {
    case JEQ: fmt = "(= %s %s)"; break;
    case JNE: fmt = "(/= %s %s)"; break;
    case JLT: fmt = "(< %s %s)"; break;
    case JGT: fmt = "(> %s %s)"; break;
    case JLE: fmt = "(<= %s %s)"; break;
    case JGE: fmt = "(>= %s %s)"; break;
    default:
      error("oops");
  }
  return format(fmt, reg_names[inst->dst.reg], src_str(inst));
}

static void xl_emit_inst(Inst* inst) {
  switch (inst->op) {
  case MOV:
    emit_line("(setq %s %s)", reg_names[inst->dst.reg], src_str(inst));
    break;

  case ADD:
    emit_line("(setq %s (logand (+ %s %s) " UINT_MAX_STR "))",
              reg_names[inst->dst.reg],
              reg_names[inst->dst.reg], src_str(inst));
    break;

  case SUB:
    emit_line("(setq %s (logand (- %s %s) " UINT_MAX_STR "))",
              reg_names[inst->dst.reg],
              reg_names[inst->dst.reg], src_str(inst));
    break;

  case LOAD:
    emit_line("(setq %s (svref mem %s))",
              reg_names[inst->dst.reg], src_str(inst));
    break;

  case STORE:
    emit_line("(si:*svset mem %s %s)", src_str(inst), reg_names[inst->dst.reg]);
    break;

  case PUTC:
    emit_line("(putchar %s)", src_str(inst));
    break;

  case GETC:
    emit_line("(setq %s (getchar))",
              reg_names[inst->dst.reg]);
    break;

  case EXIT:
    emit_line("(setq elvm-running nil)");
    break;

  case DUMP:
    break;

  case EQ:
  case NE:
  case LT:
  case GT:
  case LE:
  case GE:
    emit_line("(setq %s (if %s 1 0))",
              reg_names[inst->dst.reg], xl_cmp_str(inst));
    break;

  case JEQ:
  case JNE:
  case JLT:
  case JGT:
  case JLE:
  case JGE:
    emit_line("(if %s (setq pc (- %s 1)))",
              xl_cmp_str(inst), value_str(&inst->jmp));
    break;

  case JMP:
    emit_line("(setq pc (- %s 1))", value_str(&inst->jmp));
    break;

  default:
    error("oops");
  }
}

void target_xl(Module* module) {
  init_state_xl(module->data);
  emit_line("(defun getchar ()");
  emit_line(" (let ((c (read-char elvm-input nil)))");
  emit_line("  (if c (char-code c) 0)))");
  emit_line("(defun putchar (c)");
  emit_line(" (princ (code-char c) elvm-output))");

  int num_funcs = emit_chunked_main_loop(module->text,
                                         xl_emit_func_prologue,
                                         xl_emit_func_epilogue,
                                         xl_emit_pc_change,
                                         xl_emit_inst);

  emit_line("(defun main (&optional (input-stream *standard-input*) (output-stream *standard-output*))");
  inc_indent();
  emit_line("(setq elvm-input input-stream)");
  emit_line("(setq elvm-output output-stream)");
  for (int i = 0; i < 7; i++) {
    emit_line("(setq %s 0)", reg_names[i]);
  }
  emit_line("(setq mem (make-vector 16777216 :initial-element 0))");
  emit_line("(dolist (p mem-init)");
  emit_line(" (si:*svset mem (car p) (cdr p)))");
  emit_line("(setq elvm-running t)");
  emit_line("(while elvm-running");
  inc_indent();
  emit_line("(case (truncate pc %d)", CHUNKED_FUNC_SIZE);
  inc_indent();
  for (int i = 0; i < num_funcs; i++) {
    emit_line("(%d (elvm-func%d))", i, i);
  }
  emit_line(")))");
}
