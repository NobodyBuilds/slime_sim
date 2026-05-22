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

#ifdef __cplusplus


}
#endif