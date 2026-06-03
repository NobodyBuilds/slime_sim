#pragma once
#ifdef __cplusplus



extern "C" {
#endif
	void registerBuffer(unsigned int texId);
	void unregisterbuffer();
	void updateframe();
	void updatephysics();
	void copyparams();
	void initcuda();
	void freecuda();
	void writegenomes();
	void updategenome(int type, int var, float min, float max);

#ifdef __cplusplus


}
#endif